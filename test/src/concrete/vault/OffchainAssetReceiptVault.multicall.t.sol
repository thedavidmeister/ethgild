// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "../../../../../src/concrete/vault/OffchainAssetReceiptVault.sol";
import {OffchainAssetReceiptVaultTest, Vm} from "test/abstract/OffchainAssetReceiptVaultTest.sol";

contract MulticallTest is OffchainAssetReceiptVaultTest {
    /// Test Mint multicall
    function testMintMulticall(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 firstMintAmount,
        uint256 secondMintAmount,
        uint256 minShareRatio,
        bytes memory receiptInformation,
        string memory assetName
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Assume that firstMintAmount is not 0
        // Bound with uint64 max so next deposits doesnot cause overflow
        firstMintAmount = bound(firstMintAmount, 1, type(uint64).max);
        secondMintAmount = bound(secondMintAmount, 1, type(uint64).max);
        vm.assume(firstMintAmount != secondMintAmount);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);
        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.DEPOSITOR(), bob);

        // Prank Bob for the transaction
        vm.startPrank(bob);

        uint256 initialBalanceOwner = vault.balanceOf(bob);
        bytes[] memory data = new bytes[](2);

        data[0] = abi.encodeWithSignature(
            "mint(uint256,address,uint256,bytes)", firstMintAmount, bob, minShareRatio, receiptInformation
        );
        data[1] = abi.encodeWithSignature(
            "mint(uint256,address,uint256,bytes)", secondMintAmount, bob, minShareRatio, receiptInformation
        );

        uint256 totalMint = firstMintAmount + secondMintAmount;
        // Call multicall on redeem function
        vault.multicall(data);

        uint256 balanceAfterOwner = vault.balanceOf(bob);
        assertEq(balanceAfterOwner, initialBalanceOwner + totalMint);
        // Stop the prank
        vm.stopPrank();
    }

    /// Test Redeem multicall
    function testDepositMulticall(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 firstDepositAmount,
        uint256 secondDepositAmount,
        uint256 minShareRatio,
        bytes memory receiptInformation,
        string memory assetName
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Assume that firstDepositAmount is not 0
        // Bound with uint64 max so next deposits doesnot cause overflow
        firstDepositAmount = bound(firstDepositAmount, 1, type(uint64).max);
        secondDepositAmount = bound(secondDepositAmount, 1, type(uint64).max);
        vm.assume(firstDepositAmount != secondDepositAmount);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);
        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.DEPOSITOR(), bob);

        // Prank Bob for the transaction
        vm.startPrank(bob);

        uint256 initialBalanceOwner = vault.balanceOf(bob);
        bytes[] memory data = new bytes[](2);

        data[0] = abi.encodeWithSignature(
            "deposit(uint256,address,uint256,bytes)", firstDepositAmount, bob, minShareRatio, receiptInformation
        );
        data[1] = abi.encodeWithSignature(
            "deposit(uint256,address,uint256,bytes)", secondDepositAmount, bob, minShareRatio, receiptInformation
        );

        uint256 totalMint = firstDepositAmount + secondDepositAmount;
        // Call multicall on redeem function
        vault.multicall(data);

        uint256 balanceAfterOwner = vault.balanceOf(bob);
        assertEq(balanceAfterOwner, initialBalanceOwner + totalMint);
        // Stop the prank
        vm.stopPrank();
    }

    /// Test Redeem multicall
    function testRedeemMulticall(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 firstDepositAmount,
        uint256 secondDepositAmount,
        uint256 firstRedeemAmount,
        uint256 secondRedeemAmount,
        uint256 minShareRatio,
        bytes memory receiptInformation,
        string memory assetName
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Assume that firstDepositAmount is not 0
        // Bound with uint64 max so next deposits doesnot cause overflow
        firstDepositAmount = bound(firstDepositAmount, 1, type(uint64).max);
        secondDepositAmount = bound(secondDepositAmount, 1, type(uint64).max);
        vm.assume(firstDepositAmount != secondDepositAmount);

        firstRedeemAmount = bound(firstRedeemAmount, 1, firstDepositAmount);
        secondRedeemAmount = bound(secondRedeemAmount, 1, secondDepositAmount);

        vm.assume(firstRedeemAmount != secondRedeemAmount);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);
        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.WITHDRAWER(), bob);

        // Prank Bob for the transaction
        vm.startPrank(bob);

        // Call the deposit function
        vault.deposit(firstDepositAmount, bob, minShareRatio, receiptInformation);

        // Call another deposit deposit function
        vault.deposit(secondDepositAmount, bob, minShareRatio, receiptInformation);

        uint256 initialBalanceOwner = vault.balanceOf(bob);

        bytes[] memory data = new bytes[](2);

        data[0] = abi.encodeWithSignature(
            "redeem(uint256,address,address,uint256,bytes)", firstDepositAmount, bob, bob, 1, ""
        );
        data[1] = abi.encodeWithSignature(
            "redeem(uint256,address,address,uint256,bytes)", secondDepositAmount, bob, bob, 2, ""
        );

        uint256 totalRedeemed = firstDepositAmount + secondDepositAmount;
        // Call multicall on redeem function
        vault.multicall(data);

        uint256 balanceAfterOwner = vault.balanceOf(bob);
        assertEq(balanceAfterOwner, initialBalanceOwner - totalRedeemed);
        // Stop the prank
        vm.stopPrank();
    }

    /// Test Withdraw multicall
    function testWithdrawMulticall(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 firstDepositAmount,
        uint256 secondDepositAmount,
        uint256 firstRedeemAmount,
        uint256 secondRedeemAmount,
        uint256 minShareRatio,
        bytes memory receiptInformation,
        string memory assetName
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);
        vm.assume(alice != bob);

        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Assume that firstDepositAmount is not 0
        // Bound with uint64 max so next deposits doesnot cause overflow
        firstDepositAmount = bound(firstDepositAmount, 1, type(uint64).max);
        secondDepositAmount = bound(secondDepositAmount, 1, type(uint64).max);
        vm.assume(firstDepositAmount != secondDepositAmount);

        firstRedeemAmount = bound(firstRedeemAmount, 1, firstDepositAmount);
        secondRedeemAmount = bound(secondRedeemAmount, 1, secondDepositAmount);

        vm.assume(firstRedeemAmount != secondRedeemAmount);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);
        // Prank as Alice to grant roles
        vm.startPrank(alice);

        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.WITHDRAWER(), bob);

        // Prank Bob for the transaction
        vm.startPrank(bob);

        // Call the deposit function
        vault.deposit(firstDepositAmount, bob, minShareRatio, receiptInformation);

        // Call another deposit deposit function
        vault.deposit(secondDepositAmount, bob, minShareRatio, receiptInformation);

        uint256 initialBalanceOwner = vault.balanceOf(bob);

        bytes[] memory data = new bytes[](2);

        data[0] = abi.encodeWithSignature(
            "withdraw(uint256,address,address,uint256,bytes)", firstDepositAmount, bob, bob, 1, ""
        );
        data[1] = abi.encodeWithSignature(
            "withdraw(uint256,address,address,uint256,bytes)", secondDepositAmount, bob, bob, 2, ""
        );

        uint256 totalRedeemed = firstDepositAmount + secondDepositAmount;
        // Call multicall on redeem function
        vault.multicall(data);

        uint256 balanceAfterOwner = vault.balanceOf(bob);
        assertEq(balanceAfterOwner, initialBalanceOwner - totalRedeemed);
        // Stop the prank
        vm.stopPrank();
    }
}
