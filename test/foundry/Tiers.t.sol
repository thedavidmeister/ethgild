// SPDX-License-Identifier: CAL
pragma solidity =0.8.17;

import {VaultConfig} from "../../contracts/vault/receipt/ReceiptVault.sol";
import {CreateOffchainAssetReceiptVaultFactory} from "../../contracts/test/CreateOffchainAssetReceiptVaultFactory.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {
    OffchainAssetReceiptVault,
    UnauthorizedSenderTier
} from "../../contracts/vault/offchainAsset/OffchainAssetReceiptVault.sol";
import {OffchainAssetReceiptVaultFactory} from
    "../../contracts/vault/offchainAsset/OffchainAssetReceiptVaultFactory.sol";
import {TestErc20} from "../../contracts/test/TestErc20.sol";
import {ReadWriteTier} from "../../contracts/test/ReadWriteTier.sol";
import {OffchainAssetVaultCreator} from "./OffchainAssetVaultCreator.sol";

struct SetTierEvent {
    address sender;
    address tier;
    uint256 minimumTier;
    uint256[] context;
    bytes data;
}

contract TiersTest is Test, CreateOffchainAssetReceiptVaultFactory {
    event SetERC20Tier(address sender, address tier, uint256 minimumTier, uint256[] context, bytes data);
    event SetERC1155Tier(address sender, address tier, uint256 minimumTier, uint256[] context, bytes data);

    /// Test setERC20Tier function
    function testSetERC20Tier(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        string memory assetSymbol,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        // Start recording logs
        vm.recordLogs();
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        vault.grantRole(vault.ERC20TIERER(), alice);

        // New testErc20 contract
        ReadWriteTier TierV2TestContract = new ReadWriteTier();

        vault.setERC20Tier(address(TierV2TestContract), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the OffchainAssetReceiptVaultInitialized event log
        SetTierEvent memory eventData;
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == SetERC20Tier.selector) {
                // Decode the event data
                (address sender, address tier, uint256 minimumTier, uint256[] memory context, bytes memory data) =
                    abi.decode(logs[i].data, (address, address, uint256, uint256[], bytes));
                eventFound = true;
                eventData =
                    SetTierEvent({sender: sender, tier: tier, minimumTier: minimumTier, context: context, data: data});
                break;
            }
        }

        // Assert that the event log was found
        assertTrue(eventFound, "SetERC20Tier event log not found");

        assertEq(eventData.tier, address(TierV2TestContract));
        assertEq(eventData.sender, alice);
        assertEq(eventData.minimumTier, fuzzedMinTier);
        assertEq(eventData.context, fuzzedContext);
        assertEq(eventData.data, fuzzedData);
        vm.stopPrank();
    }

    /// Test setERC1155Tier function
    function testSetERC1155Tier(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        string memory assetSymbol,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        // Start recording logs
        vm.recordLogs();
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        vault.grantRole(vault.ERC1155TIERER(), alice);

        // New testErc20 contract
        ReadWriteTier TierV2TestContract = new ReadWriteTier();

        vault.setERC1155Tier(address(TierV2TestContract), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the OffchainAssetReceiptVaultInitialized event log
        SetTierEvent memory eventData;
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == SetERC1155Tier.selector) {
                // Decode the event data
                (address sender, address tier, uint256 minimumTier, uint256[] memory context, bytes memory data) =
                    abi.decode(logs[i].data, (address, address, uint256, uint256[], bytes));
                eventFound = true;
                eventData =
                    SetTierEvent({sender: sender, tier: tier, minimumTier: minimumTier, context: context, data: data});
                break;
            }
        }

        // Assert that the event log was found
        assertTrue(eventFound, "SetERC1155Tier event log not found");

        assertEq(eventData.tier, address(TierV2TestContract));
        assertEq(eventData.sender, alice);
        assertEq(eventData.minimumTier, fuzzedMinTier);
        assertEq(eventData.context, fuzzedContext);
        assertEq(eventData.data, fuzzedData);
        vm.stopPrank();
    }

    /// Test authorizeReceiptTransfer reverts if unauthorizedSenderTier
    function testTransferOnUnauthorizedSenderTier(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        string memory assetSymbol,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        uint256 certifyUntil,
        uint256 fuzzedBlockNumber
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyBob = bound(fuzzedKeyBob, 1, SECP256K1_ORDER - 1);
        address bob = vm.addr(fuzzedKeyBob);

        fuzzedBlockNumber = bound(fuzzedBlockNumber, 1, 1e6);
        certifyUntil = bound(certifyUntil, 1, fuzzedBlockNumber);

        vm.assume(alice != bob);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Prank as Alice for the transaction
        vm.startPrank(alice);

        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        vault.grantRole(vault.CERTIFIER(), alice);

        // Call the certify function
        vault.certify(certifyUntil, block.number, false, fuzzedData);

        vault.grantRole(vault.ERC1155TIERER(), alice);

        // New testErc20 contract
        ReadWriteTier TierV2TestContract = new ReadWriteTier();
        uint256 fromReportTime_ = TierV2TestContract.reportTimeForTier(alice, fuzzedMinTier, fuzzedContext);

        vault.setERC1155Tier(address(TierV2TestContract), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Expect the revert with the exact revert reason
        // Revert reason must match the UnauthorizedSenderTier with correct encoding
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedSenderTier.selector, alice, fromReportTime_));

        vault.authorizeReceiptTransfer(alice, bob);

        vm.stopPrank();
    }
}
