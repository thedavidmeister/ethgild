// SPDX-License-Identifier: CAL
pragma solidity =0.8.17;

import {VaultConfig} from "../../contracts/vault/receipt/ReceiptVault.sol";
import {CreateOffchainAssetReceiptVaultFactory} from "../../contracts/test/CreateOffchainAssetReceiptVaultFactory.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {
    OffchainAssetReceiptVault,
    OffchainAssetVaultConfig,
    OffchainAssetReceiptVaultConfig,
    ZeroAdmin,
    NonZeroAsset
} from "../../contracts/vault/offchainAsset/OffchainAssetReceiptVault.sol";
import {IReceiptV1} from "../../contracts/vault/receipt/IReceiptV1.sol";

contract OffChainAssetReceiptVaultTest is Test, CreateOffchainAssetReceiptVaultFactory {
    OffchainAssetVaultConfig offchainAssetVaultConfig;
    VaultConfig vaultConfig;
    OffchainAssetReceiptVault vault;

    /// Test that admin is not address zero
    function testZeroAdmin(string memory assetName, string memory assetSymbol) external {
        vaultConfig = VaultConfig({asset: address(0), name: assetName, symbol: assetSymbol});
        offchainAssetVaultConfig = OffchainAssetVaultConfig({admin: address(0), vaultConfig: vaultConfig});

        vm.expectRevert(abi.encodeWithSelector(ZeroAdmin.selector));
        vault = factory.createChildTyped(offchainAssetVaultConfig);
    }

    /// Test that asset is address zero
    function testNonZeroAsset(uint256 fuzzedKeyAlice, address asset, string memory assetName, string memory assetSymbol)
        external
    {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        vm.assume(asset != address(0));
        vaultConfig = VaultConfig({asset: asset, name: assetName, symbol: assetSymbol});
        offchainAssetVaultConfig = OffchainAssetVaultConfig({admin: alice, vaultConfig: vaultConfig});

        vm.expectRevert(abi.encodeWithSelector(NonZeroAsset.selector));
        vault = factory.createChildTyped(offchainAssetVaultConfig);
    }

    /// Test that offchainAssetReceiptVault constructs well
    function testConstruction(uint256 fuzzedKeyAlice, string memory assetName, string memory assetSymbol) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        address asset = address(0);

        vaultConfig = VaultConfig({asset: asset, name: assetName, symbol: assetSymbol});
        offchainAssetVaultConfig = OffchainAssetVaultConfig({admin: alice, vaultConfig: vaultConfig});

        vault = factory.createChildTyped(offchainAssetVaultConfig);

        assert(address(vault.asset()) == asset);
        assert(keccak256(bytes(vault.name())) == keccak256(bytes(assetName)));
        assert(keccak256(bytes(vault.symbol())) == keccak256(bytes(assetSymbol)));
    }

    /// Test that vault is the owner of its receipt
    function testVaultIsReceiptOwner(uint256 fuzzedKeyAlice, string memory assetName, string memory assetSymbol)
        external
    {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        vaultConfig = VaultConfig({asset: address(0), name: assetName, symbol: assetSymbol});
        offchainAssetVaultConfig = OffchainAssetVaultConfig({admin: alice, vaultConfig: vaultConfig});

        // Start recording logs
        vm.recordLogs();
        vault = factory.createChildTyped(offchainAssetVaultConfig);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the OffchainAssetReceiptVaultInitialized event log
        address receiptAddress = address(0);
        address msgSender = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    == keccak256(
                        "OffchainAssetReceiptVaultInitialized(address,(address,(address,(address,string,string))))"
                    )
            ) {
                // Decode the event data
                (address sender, OffchainAssetReceiptVaultConfig memory config) =
                    abi.decode(logs[i].data, (address, OffchainAssetReceiptVaultConfig));
                receiptAddress = config.receiptVaultConfig.receipt;
                msgSender = sender;
                break;
            }
        }
        // Create an instance of the Receipt contract
        IReceiptV1 receipt = IReceiptV1(receiptAddress);

        // Check that the receipt address is not zero
        assert(receiptAddress != address(0));
        // Check sender
        assert(msgSender == address(factory));

        // Interact with the receipt contract
        address owner = receipt.owner();
        assert(owner == address(vault));
    }
}
