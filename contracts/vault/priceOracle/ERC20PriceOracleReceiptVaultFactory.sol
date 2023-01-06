// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Factory} from "@rainprotocol/rain-protocol/contracts/factory/Factory.sol";
import {ERC20PriceOracleReceiptVault, ERC20PriceOracleReceiptVaultConfig, ERC20PriceOracleVaultConfig, ReceiptVaultConfig} from "./ERC20PriceOracleReceiptVault.sol";
import {Receipt, ReceiptFactory, ReceiptConfig} from "../receipt/ReceiptFactory.sol";
import {ClonesUpgradeable as Clones} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

/// @title ERC20PriceOracleReceiptVaultFactory
/// @notice Factory for creating and deploying `ERC20PriceOracleReceiptVault`.
contract ERC20PriceOracleReceiptVaultFactory is Factory {
    event SetReceiptFactory(address caller, address receiptFactory);

    /// Template contract to clone.
    /// Deployed by the constructor.
    address public immutable implementation;
    address public immutable receiptFactory;

    /// Build the reference implementation to clone for each child.
    constructor(address receiptFactory_) {
        require(receiptFactory_ != address(0), "0_RECEIPT_FACTORY");
        receiptFactory = receiptFactory_;
        emit SetReceiptFactory(msg.sender, receiptFactory_);

        address implementation_ = address(new ERC20PriceOracleReceiptVault());
        emit Implementation(msg.sender, implementation_);
        implementation = implementation_;
    }

    /// @inheritdoc Factory
    function _createChild(
        bytes memory data_
    ) internal virtual override returns (address) {
        (
            ReceiptConfig memory receiptConfig_,
            ERC20PriceOracleVaultConfig memory erc20PriceOracleVaultConfig_
        ) = abi.decode(data_, (ReceiptConfig, ERC20PriceOracleVaultConfig));
        Receipt receipt_ = ReceiptFactory(receiptFactory).createChildTyped(
            receiptConfig_
        );

        address clone_ = Clones.clone(implementation);
        receipt_.transferOwnership(clone_);

        ERC20PriceOracleReceiptVault(clone_).initialize(
            ERC20PriceOracleReceiptVaultConfig(
                erc20PriceOracleVaultConfig_.priceOracle,
                ReceiptVaultConfig(
                    address(receipt_),
                    erc20PriceOracleVaultConfig_.vaultConfig
                )
            )
        );
        return clone_;
    }

    /// Typed wrapper for `createChild` with Source.
    /// Use original `Factory` `createChild` function signature if function
    /// parameters are already encoded.
    ///
    /// @param receiptConfig_ Config for the new receipt contract that will be
    /// owned by the vault.
    /// @param erc20PriceOracleVaultConfig_ Config for the `ERC20PriceOracleReceiptVault`.
    /// @return New `ERC20PriceOracleReceiptVault` child contract address.
    function createChildTyped(
        ReceiptConfig memory receiptConfig_,
        ERC20PriceOracleVaultConfig memory erc20PriceOracleVaultConfig_
    ) external returns (ERC20PriceOracleReceiptVault) {
        return
            ERC20PriceOracleReceiptVault(
                createChild(
                    abi.encode(receiptConfig_, erc20PriceOracleVaultConfig_)
                )
            );
    }
}
