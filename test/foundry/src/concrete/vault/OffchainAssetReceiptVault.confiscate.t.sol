// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "../../../../../contracts/concrete/vault/OffchainAssetReceiptVault.sol";
import {OffchainAssetReceiptVaultTest, Vm} from "test/foundry/abstract/OffchainAssetReceiptVaultTest.sol";
import {Receipt as ReceiptContract} from "../../../../../contracts/concrete/receipt/Receipt.sol";

contract Confiscate is OffchainAssetReceiptVaultTest {
    event ConfiscateShares(address sender, address confiscatee, uint256 confiscated, bytes justification);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ConfiscateReceipt(address sender, address confiscatee, uint256 id, uint256 confiscated, bytes justification);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /// Checks that balances don't change.
    function checkConfiscateSharesNoop(OffchainAssetReceiptVault vault, address alice, address bob, bytes memory data)
        internal
    {
        uint256 initialBalanceAlice = vault.balanceOf(alice);
        uint256 initialBalanceBob = vault.balanceOf(bob);

        vault.confiscateShares(alice, data);
        bool noBalanceChange =
            initialBalanceAlice == vault.balanceOf(alice) && initialBalanceBob == vault.balanceOf(bob);

        assertTrue(noBalanceChange, "Balances should not change");
    }

    /// Checks that balances don't change.
    function checkConfiscateReceiptNoop(
        OffchainAssetReceiptVault vault,
        ReceiptContract receipt,
        address alice,
        address bob,
        uint256 id,
        bytes memory data
    ) internal {
        uint256 initialBalanceAlice = receipt.balanceOf(alice, id);
        uint256 initialBalanceBob = receipt.balanceOf(bob, id);

        // Prank as Bob for the transaction
        vm.startPrank(bob);
        vault.confiscateReceipt(alice, id, data);

        uint256 balanceAfterAlice = receipt.balanceOf(alice, id);
        uint256 balanceAfterBob = receipt.balanceOf(bob, id);

        bool noBalanceChange = initialBalanceAlice == balanceAfterAlice && initialBalanceBob == balanceAfterBob;
        assertTrue(noBalanceChange, "Balances should not change");
    }

    /// Checks that balances change.
    function checkConfiscateShares(OffchainAssetReceiptVault vault, address alice, address bob, bytes memory data)
        internal
    {
        uint256 initialBalanceAlice = vault.balanceOf(alice);
        uint256 initialBalanceBob = vault.balanceOf(bob);

        vm.expectEmit(false, false, false, true);
        emit ConfiscateShares(bob, alice, initialBalanceAlice, data);

        vm.expectEmit(false, false, false, true);
        emit Transfer(alice, bob, initialBalanceAlice);

        vault.confiscateShares(alice, data);

        bool balancesChanged =
            vault.balanceOf(alice) == 0 && vault.balanceOf(bob) == initialBalanceBob + initialBalanceAlice;

        assertTrue(balancesChanged, "Balances should change");
    }

    /// Checks that balances change.
    function checkConfiscateReceipt(
        OffchainAssetReceiptVault vault,
        ReceiptContract receipt,
        address alice,
        address bob,
        uint256 id,
        bytes memory data
    ) internal {
        uint256 initialBalanceAlice = receipt.balanceOf(alice, id);
        uint256 initialBalanceBob = receipt.balanceOf(bob, id);

        vm.expectEmit(false, false, false, true);
        emit ConfiscateReceipt(bob, alice, 1, vault.balanceOf(alice), data);

        vm.expectEmit(false, false, false, true);
        emit TransferSingle(address(vault), alice, bob, 1, vault.balanceOf(alice));

        vault.confiscateReceipt(alice, id, data);
        uint256 balanceAfterAlice = receipt.balanceOf(alice, id);
        uint256 balanceAfterBob = receipt.balanceOf(bob, id);

        bool noBalanceChange = balanceAfterAlice == 0 && balanceAfterBob == initialBalanceBob + initialBalanceAlice;
        assertTrue(noBalanceChange, "ConfiscateReceipt change balances");
    }

    /// Test to checks ConfiscateShares does not change balances on zero balance
    function testConfiscateOnZeroBalance(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        string memory assetSymbol,
        bytes memory data,
        uint256 balance,
        uint256 minShareRatio
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        minShareRatio = bound(minShareRatio, 0, 1e18);

        // Bound balance from 1 so depositing does not revert with ZeroAssetsAmount
        balance = bound(balance, 1, type(uint256).max);

        vm.assume(alice != bob);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetSymbol);

        // Prank as Alice to set role
        vm.startPrank(alice);
        vault.grantRole(vault.CONFISCATOR(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);
        // vm.stopPrank();

        // // Prank as Bob for tranactions
        vm.startPrank(bob);

        // Deposit to increase bob's balance
        vault.deposit(balance, bob, minShareRatio, data);

        checkConfiscateSharesNoop(vault, alice, bob, data);

        vm.stopPrank();
    }

    /// Test to check ConfiscateShares
    function testConfiscateShares(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 minShareRatio,
        uint256 assets,
        string memory assetName,
        string memory assetSymbol,
        bytes memory data,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        uint256 blockNumber,
        bool forceUntil
    ) external {
        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        blockNumber = bound(blockNumber, 0, type(uint256).max);
        vm.roll(blockNumber);

        referenceBlockNumber = bound(referenceBlockNumber, 0, blockNumber);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);

        vm.assume(alice != bob);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetSymbol);

        // Prank as Alice to set roles
        vm.startPrank(alice);
        vault.grantRole(vault.CONFISCATOR(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.CERTIFIER(), bob);

        // Prank as Bob for transactions
        vm.startPrank(bob);

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, data);

        // Assume that assets is less than totalSupply
        assets = bound(assets, 1, type(uint256).max);

        vault.deposit(assets, alice, minShareRatio, data);

        checkConfiscateShares(vault, alice, bob, data);
        vm.stopPrank();
    }

    /// Test to checks ConfiscateReceipt does not change balances on zero balance
    function testConfiscateReceiptOnZeroBalance(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        string memory assetName,
        string memory assetSymbol,
        bytes memory data,
        uint256 id
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        vm.assume(alice != bob);

        id = bound(id, 0, type(uint256).max);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetSymbol);

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        vault.grantRole(vault.CONFISCATOR(), bob);

        checkConfiscateReceiptNoop(vault, getReceipt(), alice, bob, id, data);
    }

    /// Test to checks ConfiscateReceipt
    function testConfiscateReceipt(
        uint256 fuzzedKeyAlice,
        uint256 fuzzedKeyBob,
        uint256 minShareRatio,
        uint256 assets,
        string memory assetName,
        bytes memory data,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        uint256 blockNumber,
        bool forceUntil
    ) external {
        minShareRatio = bound(minShareRatio, 0, 1e18);
        // Ensure the fuzzed key is within the valid range for secp256k1
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        address bob = vm.addr((fuzzedKeyBob % (SECP256K1_ORDER - 1)) + 1);

        blockNumber = bound(blockNumber, 0, type(uint256).max);
        vm.roll(blockNumber);

        referenceBlockNumber = bound(referenceBlockNumber, 0, blockNumber);
        certifyUntil = bound(certifyUntil, 1, type(uint32).max);

        // Assume that assets is less than uint256 max
        assets = bound(assets, 1, type(uint256).max);

        OffchainAssetReceiptVault vault = createVault(alice, assetName, assetName);

        vm.assume(alice != bob);
        // Prank as Alice to set roles
        vm.startPrank(alice);
        vault.grantRole(vault.CONFISCATOR(), bob);
        vault.grantRole(vault.DEPOSITOR(), bob);
        vault.grantRole(vault.CERTIFIER(), bob);

        // Prank as Bob for transactions
        vm.startPrank(bob);

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, data);

        vault.deposit(assets, alice, minShareRatio, data);

        checkConfiscateReceipt(vault, getReceipt(), alice, bob, 1, data);
        vm.stopPrank();
    }
}
