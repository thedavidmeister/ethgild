// SPDX-License-Identifier: CAL
pragma solidity =0.8.17;

import {CreateOffchainAssetReceiptVaultFactory} from "../../contracts/test/CreateOffchainAssetReceiptVaultFactory.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {
    OffchainAssetReceiptVault,
    ZeroCertifyUntil,
    FutureReferenceBlock
} from "../../contracts/vault/offchainAsset/OffchainAssetReceiptVault.sol";
import {OffchainAssetReceiptVaultFactory} from
    "../../contracts/vault/offchainAsset/OffchainAssetReceiptVaultFactory.sol";
import {OffchainAssetVaultCreator} from "./OffchainAssetVaultCreator.sol";

contract CertifyTest is Test, CreateOffchainAssetReceiptVaultFactory {
    event Certify(address sender, uint256 certifyUntil, uint256 referenceBlockNumber, bool forceUntil, bytes data);

    /// Test certify event
    function testCertify(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        string memory assetSymbol,
        uint256 certifyUntil,
        uint256 referenceBlockNumber,
        bytes memory data,
        uint256 blockNumber,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        vm.roll(blockNumber);
        referenceBlockNumber = bound(referenceBlockNumber, 0, blockNumber);
        certifyUntil = bound(certifyUntil, 1, type(uint256).max);

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        // Grant CERTIFIER role to Alice
        vault.grantRole(vault.CERTIFIER(), alice);

        // Expect the Certify event
        vm.expectEmit(false, false, false, true);
        emit Certify(alice, certifyUntil, referenceBlockNumber, forceUntil, data);

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, data);

        vm.stopPrank();
    }

    /// Test certify reverts on zero certify until
    function testCertifyRevertOnZeroCertifyUntil(
        uint256 fuzzedKeyAlice,
        uint256 referenceBlockNumber,
        string memory assetName,
        string memory assetSymbol,
        bytes memory data,
        uint256 blockNumber,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        vm.roll(blockNumber);
        referenceBlockNumber = bound(referenceBlockNumber, 0, blockNumber);

        uint256 certifyUntil = 0;

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        // Grant CERTIFIER role to Alice
        vault.grantRole(vault.CERTIFIER(), alice);

        // Expect the Certify event
        vm.expectRevert(abi.encodeWithSelector(ZeroCertifyUntil.selector, alice));

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, forceUntil, data);

        vm.stopPrank();
    }

    /// Test certify reverts on future reference
    function testCertifyRevertOnFutureReferenceBlock(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        string memory assetSymbol,
        uint256 certifyUntil,
        bytes memory data,
        uint256 fuzzedFutureBlockNumber,
        uint256 blockNumber,
        bool forceUntil
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        blockNumber = bound(block.number, 0, type(uint256).max);
        vm.roll(blockNumber);
        fuzzedFutureBlockNumber = bound(fuzzedFutureBlockNumber, blockNumber + 1, type(uint256).max - 1);

        certifyUntil = bound(certifyUntil, 1, blockNumber);

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        // Grant CERTIFIER role to Alice
        vault.grantRole(vault.CERTIFIER(), alice);

        // Expect the Certify event
        vm.expectRevert(abi.encodeWithSelector(FutureReferenceBlock.selector, alice, fuzzedFutureBlockNumber));

        // Call the certify function
        vault.certify(certifyUntil, fuzzedFutureBlockNumber, forceUntil, data);

        vm.stopPrank();
    }

    /// Test certify with force until true
    function testCertifyWithForceUntilTrue(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        string memory assetSymbol,
        uint256 certifyUntil,
        uint256 certifyUntilPast,
        uint256 referenceBlockNumber,
        bytes memory data,
        uint256 blockNumber
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256k1
        fuzzedKeyAlice = bound(fuzzedKeyAlice, 1, SECP256K1_ORDER - 1);
        address alice = vm.addr(fuzzedKeyAlice);

        blockNumber = bound(block.number, 0, type(uint256).max);
        vm.roll(blockNumber);
        referenceBlockNumber = bound(referenceBlockNumber, 0, blockNumber);
        certifyUntil = bound(certifyUntil, 1, type(uint256).max);
        vm.assume(certifyUntil > certifyUntilPast && certifyUntilPast != 0);

        // Prank as Alice for the transaction
        vm.startPrank(alice);
        OffchainAssetReceiptVault vault = OffchainAssetVaultCreator.createVault(factory, alice, assetName, assetSymbol);

        // Grant CERTIFIER role to Alice
        vault.grantRole(vault.CERTIFIER(), alice);

        // Expect the Certify event
        vm.expectEmit(false, false, false, true);
        emit Certify(alice, certifyUntil, referenceBlockNumber, false, data);

        // Call the certify function
        vault.certify(certifyUntil, referenceBlockNumber, false, data);

        // Expect the Certify event
        vm.expectEmit(false, false, false, true);
        emit Certify(alice, certifyUntilPast, referenceBlockNumber, true, data);

        // Call the certify function
        vault.certify(certifyUntilPast, referenceBlockNumber, true, data);

        vm.stopPrank();
    }
}
