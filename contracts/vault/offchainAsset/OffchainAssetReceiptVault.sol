// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ReceiptVaultConfig, VaultConfig, ReceiptVault} from "../receipt/ReceiptVault.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../receipt/IReceipt.sol";
import "@rainprotocol/rain-protocol/contracts/tier/ITierV2.sol";

/// Thrown when the account does NOT have the depositor role on mint.
error NotDepositor(address account);

/// Thrown when the account does NOT have the withdrawer role on burn.
error NotWithdrawer(address account);

/// All data required to configure an offchain asset vault except the receipt.
/// Typically the factory should build a receipt contract and transfer ownership
/// to the vault atomically during initialization so there is no opportunity for
/// an attacker to corrupt the initialzation process.
/// @param admin as per `OffchainAssetReceiptVaultConfig`.
/// @param vaultConfig MUST be used by the factory to build a
/// `ReceiptVaultConfig` once the receipt address is known and ownership has been
/// transferred to the vault contract (before initialization).
struct OffchainAssetVaultConfig {
    address admin;
    VaultConfig vaultConfig;
}

/// All data required to construct `CertifiedAssetConnect`.
/// @param admin The initial admin has ALL ROLES. It is up to the admin to
/// appropriately delegate and renounce roles or to be a smart contract with
/// formal governance processes. In general a single EOA holding all admin roles
/// is completely insecure and counterproductive as it allows a single address
/// to both mint and audit assets (and many other things).
/// @param receiptConfig Forwarded to ReceiptVault.
struct OffchainAssetReceiptVaultConfig {
    address admin;
    ReceiptVaultConfig receiptVaultConfig;
}

/// @title OffchainAssetReceiptVault
/// @notice Enables curators of offchain assets to create a token that they can
/// arbitrage offchain assets against onchain assets. This allows them to
/// maintain a peg between offchain and onchain markets.
///
/// At a high level this works because the custodian can always profitably trade
/// the peg against offchain markets in both directions.
///
/// Price is higher onchain: Custodian can buy/produce assets offchain and mint
/// tokens then sell the tokens for more than the assets would sell for offchain
/// thus making a profit. The sale of the tokens brings the onchain price down.
/// Price is higher offchain: Custodian can sell assets offchain and
/// buyback+burn tokens onchain for less than the offchain sale, thus making a
/// profit. The token purchase brings the onchain price up.
///
/// In contrast to pure algorithmic tokens and sentiment based stablecoins, a
/// competent custodian can profit "infinitely" to maintain the peg no matter
/// how badly the peg breaks. As long as every token is fully collateralised by
/// liquid offchain assets, tokens can be profitably bought and burned by the
/// custodian all the way to 0 token supply.
///
/// This model is contingent on existing onchain and offchain liquidity
/// and the custodian being competent. These requirements are non-trivial. There
/// are far more incompetent and malicious custodians than competent ones. Only
/// so many bars of gold can fit in a vault, and only so many trees that can
/// live in a forest.
///
/// This contract does not attempt to solve for liquidity and trustworthyness,
/// it only seeks to provide baseline functionality that a competent custodian
/// will need to tackle the problem. The implementation provides:
///
/// - `ReceiptVault` base that allows transparent onchain/offchain audit history
/// - Certifier role that allows for audits of offchain assets that can fail
/// - KYC/membership lists that can restrict who can hold/transfer assets as
///   any Rain `ITierV2` interface
/// - Ability to comply with sanctions/regulators by confiscating assets
/// - `ERC20` shares in the vault that can be traded minted/burned to track a peg
/// - `ERC4626` compliant vault interface (inherited from `ReceiptVault`)
/// - Fine grained standard Open Zeppelin access control for all system roles
/// - Snapshots from `ReceiptVault` exposed under a role to ease potential
///   future migrations or disaster recovery plans.
contract OffchainAssetReceiptVault is ReceiptVault, AccessControl {
    /// Contract has initialized.
    /// @param caller The `msg.sender` constructing the contract.
    /// @param config All initialization config.
    event OffchainAssetVaultInitialized(
        address caller,
        OffchainAssetReceiptVaultConfig config
    );

    /// A new certification time has been set.
    /// @param caller The certifier setting the new time.
    /// @param until The time the system is certified until. Normally this will
    /// be a future time but certifiers MAY set it to a time in the past which
    /// will immediately freeze all transfers.
    /// @param data The certifier MAY provide additional supporting data such
    /// as an auditor's report/comments etc.
    event Certify(address caller, uint256 until, bytes data);

    /// Shares have been confiscated from a user who is not currently meeting
    /// the ERC20 tier contract minimum requirements.
    /// @param caller The confiscator who is confiscating the shares.
    /// @param confiscatee The user who had their shares confiscated.
    /// @param confiscated The amount of shares that were confiscated.
    event ConfiscateShares(
        address caller,
        address confiscatee,
        uint256 confiscated
    );

    /// A receipt has been confiscated from a user who is not currently meeting
    /// the ERC1155 tier contract minimum requirements.
    /// @param caller The confiscator who is confiscating the receipt.
    /// @param confiscatee The user who had their receipt confiscated.
    /// @param id The receipt ID that was confiscated.
    /// @param confiscated The amount of the receipt that was confiscated.
    event ConfiscateReceipt(
        address caller,
        address confiscatee,
        uint256 id,
        uint256 confiscated
    );

    /// A new ERC20 tier contract has been set.
    /// @param caller `msg.sender` who set the new tier contract.
    /// @param tier New tier contract used for all ERC20 transfers and
    /// confiscations.
    /// @param minimumTier Minimum tier that a user must hold to be eligible
    /// to send/receive/hold shares and be immune to share confiscations.
    /// @param context OPTIONAL additional context to pass to ITierV2 calls.
    event SetERC20Tier(
        address caller,
        address tier,
        uint256 minimumTier,
        uint256[] context
    );

    /// A new ERC1155 tier contract has been set.
    /// @param caller `msg.sender` who set the new tier contract.
    /// @param tier New tier contract used for all ERC1155 transfers and
    /// confiscations.
    /// @param minimumTier Minimum tier that a user must hold to be eligible
    /// to send/receive/hold receipts and be immune to receipt confiscations.
    /// @param context OPTIONAL additional context to pass to ITierV2 calls.
    event SetERC1155Tier(
        address caller,
        address tier,
        uint256 minimumTier,
        uint256[] context
    );

    /// Rolename for depositors.
    /// Depositor role is required to mint new shares and receipts.
    bytes32 public constant DEPOSITOR = keccak256("DEPOSITOR");
    /// Rolename for depositor admins.
    bytes32 public constant DEPOSITOR_ADMIN = keccak256("DEPOSITOR_ADMIN");

    /// Rolename for withdrawers.
    /// Withdrawer role is required to burn shares and receipts.
    bytes32 public constant WITHDRAWER = keccak256("WITHDRAWER");
    /// Rolename for withdrawer admins.
    bytes32 public constant WITHDRAWER_ADMIN = keccak256("WITHDRAWER_ADMIN");

    /// Rolename for certifiers.
    /// Certifier role is required to extend the `certifiedUntil` time.
    bytes32 public constant CERTIFIER = keccak256("CERTIFIER");
    /// Rolename for certifier admins.
    bytes32 public constant CERTIFIER_ADMIN = keccak256("CERTIFIER_ADMIN");

    /// Rolename for handlers.
    /// Handler role is required to accept tokens during system freeze.
    bytes32 public constant HANDLER = keccak256("HANDLER");
    /// Rolename for handler admins.
    bytes32 public constant HANDLER_ADMIN = keccak256("HANDLER_ADMIN");

    /// Rolename for ERC20 tierer.
    /// ERC20 tierer role is required to modify the tier contract for shares.
    bytes32 public constant ERC20TIERER = keccak256("ERC20TIERER");
    /// Rolename for ERC20 tierer admins.
    bytes32 public constant ERC20TIERER_ADMIN = keccak256("ERC20TIERER_ADMIN");

    /// Rolename for ERC1155 tierer.
    /// ERC1155 tierer role is required to modify the tier contract for receipts.
    bytes32 public constant ERC1155TIERER = keccak256("ERC1155TIERER");
    /// Rolename for ERC1155 tierer admins.
    bytes32 public constant ERC1155TIERER_ADMIN =
        keccak256("ERC1155TIERER_ADMIN");

    /// Rolename for ERC20 snapshotter.
    /// ERC20 snapshotter role is required to snapshot shares.
    bytes32 public constant ERC20SNAPSHOTTER = keccak256("ERC20SNAPSHOTTER");
    /// Rolename for ERC20 snapshotter admins.
    bytes32 public constant ERC20SNAPSHOTTER_ADMIN =
        keccak256("ERC20SNAPSHOTTER_ADMIN");

    /// Rolename for confiscator.
    /// Confiscator role is required to confiscate shares and/or receipts.
    bytes32 public constant CONFISCATOR = keccak256("CONFISCATOR");
    /// Rolename for confiscator admins.
    bytes32 public constant CONFISCATOR_ADMIN = keccak256("CONFISCATOR_ADMIN");

    /// The largest issued id. The next id issued will be larger than this.
    uint256 private highwaterId;

    /// The system is certified until this timestamp. If this is in the past then
    /// general transfers of shares and receipts will fail until the system can
    /// be certified to a future time.
    uint32 private certifiedUntil;

    /// The minimum tier required for an address to receive shares.
    uint8 private erc20MinimumTier;
    /// The `ITierV2` contract that defines the current tier of each address for
    /// the purpose of receiving shares.
    ITierV2 private erc20Tier;
    /// Optional context to provide to the `ITierV2` contract when calculating
    /// any addresses' tier for the purpose of receiving shares. Global to all
    /// addresses.
    uint256[] private erc20TierContext;

    /// The minimum tier required for an address to receive receipts.
    uint8 private erc1155MinimumTier;
    /// The `ITierV2` contract that defines the current tier of each address for
    /// the purpose of receiving receipts.
    ITierV2 private erc1155Tier;
    /// Optional context to provide to the `ITierV2` contract when calculating
    /// any addresses' tier for the purpose of receiving receipts. Global to all
    /// addresses.
    uint256[] private erc1155TierContext;

    /// Initializes the initial admin and the underlying `ReceiptVault`.
    /// The admin provided will be admin of all roles and can reassign and revoke
    /// this as appropriate according to standard Open Zeppelin access control
    /// logic.
    /// @param config_ All config required to initialize.
    function initialize(
        OffchainAssetReceiptVaultConfig memory config_
    ) external initializer {
        __ReceiptVault_init(config_.receiptVaultConfig);
        __AccessControl_init();

        // There is no asset, the asset is offchain.
        require(
            config_.receiptVaultConfig.vaultConfig.asset == address(0),
            "NONZERO_ASSET"
        );

        _setRoleAdmin(DEPOSITOR_ADMIN, DEPOSITOR_ADMIN);
        _setRoleAdmin(DEPOSITOR, DEPOSITOR_ADMIN);

        _setRoleAdmin(WITHDRAWER_ADMIN, WITHDRAWER_ADMIN);
        _setRoleAdmin(WITHDRAWER, WITHDRAWER_ADMIN);

        _setRoleAdmin(CERTIFIER_ADMIN, CERTIFIER_ADMIN);
        _setRoleAdmin(CERTIFIER, CERTIFIER_ADMIN);

        _setRoleAdmin(HANDLER_ADMIN, HANDLER_ADMIN);
        _setRoleAdmin(HANDLER, HANDLER_ADMIN);

        _setRoleAdmin(ERC20TIERER_ADMIN, ERC20TIERER_ADMIN);
        _setRoleAdmin(ERC20TIERER, ERC20TIERER_ADMIN);

        _setRoleAdmin(ERC1155TIERER_ADMIN, ERC1155TIERER_ADMIN);
        _setRoleAdmin(ERC1155TIERER, ERC1155TIERER_ADMIN);

        _setRoleAdmin(ERC20SNAPSHOTTER_ADMIN, ERC20SNAPSHOTTER_ADMIN);
        _setRoleAdmin(ERC20SNAPSHOTTER, ERC20SNAPSHOTTER_ADMIN);

        _setRoleAdmin(CONFISCATOR_ADMIN, CONFISCATOR_ADMIN);
        _setRoleAdmin(CONFISCATOR, CONFISCATOR_ADMIN);

        _grantRole(DEPOSITOR_ADMIN, config_.admin);
        _grantRole(WITHDRAWER_ADMIN, config_.admin);
        _grantRole(CERTIFIER_ADMIN, config_.admin);
        _grantRole(HANDLER_ADMIN, config_.admin);
        _grantRole(ERC20TIERER_ADMIN, config_.admin);
        _grantRole(ERC1155TIERER_ADMIN, config_.admin);
        _grantRole(ERC20SNAPSHOTTER_ADMIN, config_.admin);
        _grantRole(CONFISCATOR_ADMIN, config_.admin);

        emit OffchainAssetVaultInitialized(msg.sender, config_);
    }

    /// Ensure that only callers with the depositor role can deposit.
    /// @inheritdoc ReceiptVault
    function _beforeDeposit(
        uint256,
        address,
        uint256,
        uint256
    ) internal view override {
        if (!hasRole(DEPOSITOR, msg.sender)) {
            revert NotDepositor(msg.sender);
        }
    }

    /// Ensure that only owners with the withdrawer role can withdraw.
    /// @inheritdoc ReceiptVault
    function _afterWithdraw(
        uint256,
        address,
        address owner_,
        uint256,
        uint256
    ) internal view override {
        if (!hasRole(WITHDRAWER, owner_)) {
            revert NotWithdrawer(owner_);
        }
    }

    /// Shares total supply is 1:1 with offchain assets.
    /// Assets aren't real so only way to report this is to return the total
    /// supply of shares.
    /// @inheritdoc ReceiptVault
    function totalAssets() external view override returns (uint256) {
        return totalSupply();
    }

    /// Reverts are disallowed so `0` for everyone who does not have the role
    /// for depositing. Depositors all have the same global share ratio.
    /// @inheritdoc ReceiptVault
    function _shareRatio(
        address depositor_,
        address
    ) internal view override returns (uint256) {
        // Passthrough to global share ratio if account has correct role.
        return hasRole(DEPOSITOR, depositor_) ? _shareRatio() : 0;
    }

    function previewWithdraw(
        uint256 assets_,
        uint256 id_
    ) public view override returns (uint256) {
        return
            hasRole(WITHDRAWER, msg.sender)
                ? super.previewWithdraw(assets_, id_)
                : 0;
    }

    function previewMint(
        uint256 shares_
    ) public view override returns (uint256) {
        return hasRole(DEPOSITOR, msg.sender) ? super.previewMint(shares_) : 0;
    }

    function previewRedeem(
        uint256 shares_,
        uint256 id_
    ) public view override returns (uint256) {
        return
            hasRole(WITHDRAWER, msg.sender)
                ? super.previewRedeem(shares_, id_)
                : 0;
    }

    /// @inheritdoc ReceiptVault
    function _nextId() internal override returns (uint256) {
        uint256 id_ = highwaterId + 1;
        highwaterId = id_;
        return id_;
    }

    function authorizeReceiptInformation(
        address account_,
        uint256 id_,
        bytes memory
    ) external view virtual override {
        // Only receipt holders and certifiers can assert things about offchain
        // assets.
        require(
            IReceipt(_receipt).balanceOf(account_, id_) > 0 ||
                hasRole(CERTIFIER, account_),
            "ASSET_INFORMATION_AUTH"
        );
    }

    /// Receipt holders who are also depositors can increase the deposit amount
    /// for the existing id of this receipt. It is STRONGLY RECOMMENDED the
    /// redepositor also provides data to be forwarded to asset information to
    /// justify the additional deposit. New offchain assets MUST NOT redeposit
    /// under existing IDs, deposit under a new id instead.
    /// @param assets_ As per IERC4626 `deposit`.
    /// @param receiver_ As per IERC4626 `deposit`.
    /// @param id_ The existing receipt to despoit additional assets under. Will
    /// mint new ERC20 shares and also increase the held receipt amount 1:1.
    /// @param receiptInformation_ Forwarded to receipt mint and
    /// `receiptInformation`.
    function redeposit(
        uint256 assets_,
        address receiver_,
        uint256 id_,
        bytes calldata receiptInformation_
    ) external returns (uint256) {
        // This is stricter than the standard "or certifier" check.
        require(
            IReceipt(_receipt).balanceOf(msg.sender, id_) > 0,
            "NOT_RECEIPT_HOLDER"
        );
        _deposit(
            assets_,
            receiver_,
            _shareRatio(msg.sender, receiver_),
            id_,
            receiptInformation_
        );
        return assets_;
    }

    function snapshot() external onlyRole(ERC20SNAPSHOTTER) returns (uint256) {
        return _snapshot();
    }

    /// @param tier_ `ITier` contract to check reports from. MAY be `0` to
    /// disable report checking.
    /// @param minimumTier_ The minimum tier to be held according to `tier_`.
    function setERC20Tier(
        address tier_,
        uint8 minimumTier_,
        uint256[] calldata context_
    ) external onlyRole(ERC20TIERER) {
        erc20Tier = ITierV2(tier_);
        erc20MinimumTier = minimumTier_;
        erc20TierContext = context_;
        emit SetERC20Tier(msg.sender, tier_, minimumTier_, context_);
    }

    /// @param tier_ `ITier` contract to check reports from. MAY be `0` to
    /// disable report checking.
    /// @param minimumTier_ The minimum tier to be held according to `tier_`.
    function setERC1155Tier(
        address tier_,
        uint8 minimumTier_,
        uint256[] calldata context_
    ) external onlyRole(ERC1155TIERER) {
        erc1155Tier = ITierV2(tier_);
        erc1155MinimumTier = minimumTier_;
        erc1155TierContext = context_;
        emit SetERC1155Tier(msg.sender, tier_, minimumTier_, context_);
    }

    function certify(
        uint32 until_,
        bytes calldata data_,
        bool forceUntil_
    ) external onlyRole(CERTIFIER) {
        // A certifier can set `forceUntil_` to true to force a _decrease_ in
        // the `certifiedUntil` time, which is unusual but MAY need to be done
        // in the case of rectifying a prior mistake.
        if (forceUntil_ || until_ > certifiedUntil) {
            certifiedUntil = until_;
        }
        emit Certify(msg.sender, until_, data_);
    }

    function enforceValidTransfer(
        ITierV2 tier_,
        uint256 minimumTier_,
        uint256[] memory tierContext_,
        address from_,
        address to_
    ) internal view {
        // Handlers can ALWAYS send and receive funds.
        // Handlers bypass BOTH the timestamp on certification AND tier based
        // restriction.
        if (hasRole(HANDLER, from_) || hasRole(HANDLER, to_)) {
            return;
        }

        // Minting and burning is always allowed as it is controlled via. RBAC
        // separately to the tier contracts. Minting and burning is ALSO valid
        // after the certification expires as it is likely the only way to
        // repair the system and bring it back to a certifiable state.
        if (from_ == address(0) || to_ == address(0)) {
            return;
        }

        // Confiscation is always allowed as it likely represents some kind of
        // regulatory/legal requirement. It may also be required to satisfy
        // certification requirements.
        if (hasRole(CONFISCATOR, to_)) {
            return;
        }

        // Everyone else can only transfer while the certification is valid.
        //solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= certifiedUntil, "CERTIFICATION_EXPIRED");

        // If there is a tier contract we enforce it.
        if (address(tier_) != address(0) && minimumTier_ > 0) {
            // The sender must have a valid tier.
            require(
                block.timestamp >=
                    tier_.reportTimeForTier(from_, minimumTier_, tierContext_),
                "SENDER_TIER"
            );
            // The recipient must have a valid tier.
            require(
                block.timestamp >=
                    tier_.reportTimeForTier(to_, minimumTier_, tierContext_),
                "RECIPIENT_TIER"
            );
        }
    }

    // @inheritdoc ERC20
    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256
    ) internal view override {
        enforceValidTransfer(
            erc20Tier,
            erc20MinimumTier,
            erc20TierContext,
            from_,
            to_
        );
    }

    function authorizeReceiptTransfer(
        address from_,
        address to_
    ) external view virtual override {
        enforceValidTransfer(
            erc1155Tier,
            erc1155MinimumTier,
            erc1155TierContext,
            from_,
            to_
        );
    }

    /// Confiscators can confiscate ERC20 vault shares from `confiscatee_`.
    function confiscateShares(
        address confiscatee_
    ) external nonReentrant onlyRole(CONFISCATOR) returns (uint256) {
        uint256 confiscatedShares_ = 0;
        if (
            address(erc20Tier) == address(0) ||
            block.timestamp <
            erc20Tier.reportTimeForTier(
                confiscatee_,
                erc20MinimumTier,
                erc20TierContext
            )
        ) {
            confiscatedShares_ = balanceOf(confiscatee_);
            if (confiscatedShares_ > 0) {
                _transfer(confiscatee_, msg.sender, confiscatedShares_);
            }
        }
        emit ConfiscateShares(msg.sender, confiscatee_, confiscatedShares_);
        return confiscatedShares_;
    }

    function confiscateReceipt(
        address confiscatee_,
        uint256 id_
    ) external nonReentrant onlyRole(CONFISCATOR) returns (uint256) {
        uint256 confiscatedReceiptAmount_ = 0;
        if (
            address(erc1155Tier) == address(0) ||
            block.timestamp <
            erc1155Tier.reportTimeForTier(
                confiscatee_,
                erc1155MinimumTier,
                erc1155TierContext
            )
        ) {
            IReceipt receipt_ = IReceipt(_receipt);
            confiscatedReceiptAmount_ = IReceipt(receipt_).balanceOf(
                confiscatee_,
                id_
            );
            if (confiscatedReceiptAmount_ > 0) {
                receipt_.ownerTransferFrom(
                    confiscatee_,
                    msg.sender,
                    id_,
                    confiscatedReceiptAmount_,
                    ""
                );
            }
        }
        // Slither flags this as reentrant but this function has `nonReentrant`
        // on it from `ReentrancyGuard`.
        //slither-disable-next-line reentrancy-vulnerabilities-3
        emit ConfiscateReceipt(
            msg.sender,
            confiscatee_,
            id_,
            confiscatedReceiptAmount_
        );
        return confiscatedReceiptAmount_;
    }
}
