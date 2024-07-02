// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    UnauthorizedSenderTier,
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfig
} from "../../../../../contracts/concrete/vault/OffchainAssetReceiptVault.sol";
import {OffchainAssetReceiptVaultTest, Vm} from "test/foundry/abstract/OffchainAssetReceiptVaultTest.sol";
import {LibOffchainAssetVaultCreator} from "test/foundry/lib/LibOffchainAssetVaultCreator.sol";
import {ITierV2} from "rain.tier.interface/interface/ITierV2.sol";
import {Receipt as ReceiptContract} from "../../../../../contracts/concrete/receipt/Receipt.sol";
import "forge-std/console.sol";

contract TiersTest is OffchainAssetReceiptVaultTest {
    event SetERC20Tier(address sender, address tier, uint256 minimumTier, uint256[] context, bytes data);
    event SetERC1155Tier(address sender, address tier, uint256 minimumTier, uint256[] context, bytes data);
    event OffchainAssetReceiptVaultInitialized(address sender, OffchainAssetReceiptVaultConfig config);

    /// Get Receipt from event
    function getReceipt() internal returns (ReceiptContract) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the OffchainAssetReceiptVaultInitialized event log
        address receiptAddress = address(0);
        bool eventFound = false; // Flag to indicate whether the event log was found
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == OffchainAssetReceiptVaultInitialized.selector) {
                // Decode the event data
                (, OffchainAssetReceiptVaultConfig memory config) =
                    abi.decode(logs[i].data, (address, OffchainAssetReceiptVaultConfig));
                receiptAddress = config.receiptVaultConfig.receipt;
                eventFound = true; // Set the flag to true since event log was found
                break;
            }
        }

        // Assert that the event log was found
        assertTrue(eventFound, "OffchainAssetReceiptVaultInitialized event log not found");
        // Return an receipt contract
        return ReceiptContract(receiptAddress);
    }

    /// Test setERC20Tier event
    function testSetERC20Tier(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        string memory assetSymbol,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        address tier
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetSymbol);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        // Grant the necessary role
        vault.grantRole(vault.ERC20TIERER(), bob);
        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        // Emit the expected event
        vm.expectEmit(true, true, true, true);
        emit SetERC20Tier(bob, address(tier), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Call the function that should emit the event
        vault.setERC20Tier(address(tier), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Stop the prank
        vm.stopPrank();
    }

    /// Test setERC1155Tier event
    function testSetERC1155Tier(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        string memory assetSymbol,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        address tier
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetSymbol);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        // Grant the necessary role
        vault.grantRole(vault.ERC1155TIERER(), bob);
        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        // Emit the expected event
        vm.expectEmit(true, true, true, true);
        emit SetERC1155Tier(bob, tier, fuzzedMinTier, fuzzedContext, fuzzedData);

        // Call the function that should emit the event
        vault.setERC1155Tier(tier, fuzzedMinTier, fuzzedContext, fuzzedData);

        // Stop the prank
        vm.stopPrank();
    }

    /// Test authorizeReceiptTransfer reverts if unauthorizedSenderTier
    function testTransferOnUnauthorizedSenderTier(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        address tierAddress,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        referenceBlockNumber = bound(referenceBlockNumber, 1, block.number);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);

        vm.assume(alice != bob);
        vm.assume(tierAddress != address(0));

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.CERTIFIER(), bob);
        vault.grantRole(vault.ERC1155TIERER(), bob);

        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, fuzzedData);

        vault.setERC1155Tier(tierAddress, fuzzedMinTier, fuzzedContext, fuzzedData);

        {
            ITierV2 tierContract = ITierV2(tierAddress);
            vm.mockCall(
                address(tierContract),
                abi.encodeWithSelector(ITierV2.reportTimeForTier.selector, bob, fuzzedMinTier, fuzzedContext),
                abi.encode(999)
            );

            //Expect the revert with the exact revert reason
            vm.expectRevert();

            vault.authorizeReceiptTransfer(bob, alice);
        }
        vm.stopPrank();
    }

    /// Test authorizeReceiptTransfer reverts on random tier address
    function testAuthorizeReceiptTransferOnRandomTier(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        uint256 timestamp,
        address tierAddress,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        referenceBlockNumber = bound(referenceBlockNumber, 1, block.number);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);
        timestamp = bound(timestamp, 1, certifyUntil);
        vm.assume(tierAddress != address(0));

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.CERTIFIER(), bob);
        vault.grantRole(vault.ERC1155TIERER(), bob);

        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        vm.warp(timestamp);
        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, fuzzedData);

        vault.setERC1155Tier(tierAddress, fuzzedMinTier, fuzzedContext, fuzzedData);

        {
            vm.mockCall(
                tierAddress,
                abi.encodeWithSelector(ITierV2.reportTimeForTier.selector, bob, fuzzedMinTier, fuzzedContext),
                abi.encode(false) // Set the response to false to simulate a revert
            );

            vm.expectRevert();
            vault.authorizeReceiptTransfer(bob, alice);
        }
        vm.stopPrank();
    }

    /// Test ERC20 tier contract controls token movement
    function testERC20TierControlsTokenMovement(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        address tier,
        uint256 certifyUntil,
        uint256 transferAmount,
        bool forceUntil,
        uint256 minShareRatio
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        // referenceBlockNumber = bound(referenceBlockNumber, 0, block.number);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);
        transferAmount = bound(transferAmount, 1, type(uint256).max);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));
        minShareRatio = bound(minShareRatio, 0, 1e18);
        vm.assume(tier != address(0));
        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        // Grant the necessary role
        vault.grantRole(vault.ERC20TIERER(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.CERTIFIER(), bob);
        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        vault.certify(certifyUntil, block.number, forceUntil, fuzzedData);

        // Set the tier for token movement restriction
        vault.setERC20Tier(tier, fuzzedMinTier, fuzzedContext, fuzzedData);

        // Try to move tokens (should be restricted)
        vm.expectRevert();
        vault.deposit(transferAmount, alice, minShareRatio, fuzzedData);

        // Change the tier contract to one that allows token movement
        vault.setERC20Tier(address(0), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Transfer tokens should succeed
        vault.deposit(transferAmount, alice, minShareRatio, fuzzedData);

        // Stop the prank
        vm.stopPrank();
    }

    /// Test ERC1155 tier contract controls token movement
    function testERC1155TierControlsTokenMovement(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        bytes memory fuzzedData,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        address tier,
        uint256 certifyUntil,
        uint256 transferAmount,
        bool forceUntil,
        uint256 minShareRatio
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        // referenceBlockNumber = bound(referenceBlockNumber, 0, block.number);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);
        transferAmount = bound(transferAmount, 1, type(uint256).max);

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));
        minShareRatio = bound(minShareRatio, 0, 1e18);
        vm.assume(tier != address(0));
        // Create the vault
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        // Grant the necessary role
        vault.grantRole(vault.ERC1155TIERER(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.CERTIFIER(), bob);
        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);

        vault.certify(certifyUntil, block.number, forceUntil, fuzzedData);

        // Set the tier for token movement restriction
        vault.setERC1155Tier(tier, fuzzedMinTier, fuzzedContext, fuzzedData);

        // Try to move tokens (should be restricted)
        vm.expectRevert();
        vault.deposit(transferAmount, alice, minShareRatio, fuzzedData);

        // Change the tier contract to one that allows token movement
        vault.setERC1155Tier(address(0), fuzzedMinTier, fuzzedContext, fuzzedData);

        // Transfer tokens should succeed
        vault.deposit(transferAmount, alice, minShareRatio, fuzzedData);

        // Stop the prank
        vm.stopPrank();
    }

    /// Test testReceiptTransfer
    function testReceiptTransfer(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        uint8 fuzzedMinTier,
        uint256[] memory fuzzedContext,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        address tierAddress,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        referenceBlockNumber = bound(referenceBlockNumber, 1, block.number);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);

        vm.assume(alice != bob);
        vm.assume(tierAddress != address(0));

        fuzzedMinTier = uint8(bound(fuzzedMinTier, uint256(1), uint256(8)));

        // Start recording logs
        vm.recordLogs();
        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);
        ReceiptContract receipt = getReceipt();

        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.CERTIFIER(), bob);
        vault.grantRole(vault.ERC20TIERER(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);

        vm.stopPrank();

        // Prank as Bob
        vm.startPrank(bob);
        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, bytes(""));

        vm.warp(certifyUntil);

        // Cannot fuzz assets value due to variable limits
        vault.deposit(100, bob, 1, bytes(""));

        {
            ITierV2 tierContract = ITierV2(tierAddress);
            vault.setERC20Tier(address(tierContract), fuzzedMinTier, fuzzedContext, bytes(""));

            vm.mockCall(
                address(tierContract),
                abi.encodeWithSelector(ITierV2.reportTimeForTier.selector, bob, fuzzedMinTier, fuzzedContext),
                abi.encode(10)
            );

            vault.authorizeReceiptTransfer(bob, alice);

            receipt.safeTransferFrom(bob, alice, 1, 10, bytes(""));
            assertEq(receipt.balanceOf(alice, 1), 10);
        }
        vm.stopPrank();
    }
}
