// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    ERC20PriceOracleReceiptVault,
    ERC20PriceOracleReceiptVaultConfig
} from "../../../../../contracts/concrete/vault/ERC20PriceOracleReceiptVault.sol";
import {ERC20PriceOracleReceiptVaultTest, Vm} from "test/foundry/abstract/ERC20PriceOracleReceiptVaultTest.sol";
import {TwoPriceOracle} from "../../../../../contracts/oracle/price/TwoPriceOracle.sol";
import {
    LibFixedPointDecimalArithmeticOpenZeppelin,
    Math
} from "rain.math.fixedpoint/lib/LibFixedPointDecimalArithmeticOpenZeppelin.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Receipt as ReceiptContract} from "../../../../../contracts/concrete/receipt/Receipt.sol";

import "forge-std/console.sol";

contract ERC20PriceOracleReceiptVaultWithdrawTest is ERC20PriceOracleReceiptVaultTest {
    using LibFixedPointDecimalArithmeticOpenZeppelin for uint256;

    event WithdrawWithReceipt(
        address sender,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 id,
        bytes receiptInformation
    );
    event ERC20PriceOracleReceiptVaultInitialized(address sender, ERC20PriceOracleReceiptVaultConfig config);
    /// Get Receipt from event

    function getReceipt() internal returns (ReceiptContract) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the ERC20PriceOracleReceiptVaultInitialized event log
        address receiptAddress = address(0);
        bool eventFound = false; // Flag to indicate whether the event log was found
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ERC20PriceOracleReceiptVaultInitialized.selector) {
                // Decode the event data
                (, ERC20PriceOracleReceiptVaultConfig memory config) =
                    abi.decode(logs[i].data, (address, ERC20PriceOracleReceiptVaultConfig));
                receiptAddress = config.receiptVaultConfig.receipt;
                eventFound = true; // Set the flag to true since event log was found
                break;
            }
        }
        // Assert that the event log was found
        assertTrue(eventFound, "ERC20PriceOracleReceiptVaultInitialized event log not found");
        // Return an receipt contract
        return ReceiptContract(receiptAddress);
    }

    /// Checks that balance owner balance changes after wirthdraw
    function checkBalanceChange(
        ERC20PriceOracleReceiptVault vault,
        address receiver,
        address owner,
        uint256 id,
        uint256 assets,
        ReceiptContract receipt,
        bytes memory data
    ) internal {
        uint256 initialBalanceOwner = receipt.balanceOf(owner, id);
        uint256 shares = assets.fixedPointMul(id, Math.Rounding.Up);

        // Set up the event expectation for WithdrawWithReceipt
        vm.expectEmit(true, true, true, true);
        emit WithdrawWithReceipt(owner, receiver, owner, assets, shares, id, data);

        // Call withdraw function
        vault.withdraw(assets, receiver, owner, id, data);

        uint256 balanceAfterOwner = receipt.balanceOf(owner, id);
        assertEq(balanceAfterOwner, initialBalanceOwner - shares);
    }

    /// Checks that balance owner balance does not change after wirthdraw revert
    function checkNoBalanceChange(
        ERC20PriceOracleReceiptVault vault,
        address receiver,
        address owner,
        uint256 id,
        uint256 assets,
        bytes memory data,
        bytes memory expectedRevertData
    ) internal {
        uint256 initialBalanceOwner = vault.balanceOf(owner);

        // Check if expectedRevertData is provided
        if (expectedRevertData.length > 0) {
            vm.expectRevert(expectedRevertData);
        } else {
            vm.expectRevert();
        }
        // Call withdraw function
        vault.withdraw(assets, receiver, owner, id, data);

        uint256 balanceAfterOwner = vault.balanceOf(owner);
        assertEq(balanceAfterOwner, initialBalanceOwner);
    }

    /// Test Withdraw function
    function testWithdraw(
        uint256 fuzzedKeyAlice,
        string memory assetName,
        uint256 timestamp,
        uint256 assets,
        uint8 xauDecimals,
        uint8 usdDecimals,
        uint80 answeredInRound
    ) external {
        // Ensure the fuzzed key is within the valid range for secp256
        address alice = vm.addr((fuzzedKeyAlice % (SECP256K1_ORDER - 1)) + 1);
        // Use common decimal bounds for price feeds
        // Use 0-20 so we at least have some coverage higher than 18
        usdDecimals = uint8(bound(usdDecimals, 0, 20));
        xauDecimals = uint8(bound(xauDecimals, 0, 20));
        timestamp = bound(timestamp, 0, type(uint32).max);

        vm.warp(timestamp);
        TwoPriceOracle twoPriceOracle = createTwoPriceOracle(usdDecimals, usdDecimals, timestamp, answeredInRound);
        vm.startPrank(alice);
        // Start recording logs
        vm.recordLogs();
        ERC20PriceOracleReceiptVault vault = createVault(address(twoPriceOracle), assetName, assetName);
        ReceiptContract receipt = getReceipt();

        vm.mockCall(address(iAsset), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1e18));
        // Ensure Alice has enough balance and allowance
        vm.mockCall(address(iAsset), abi.encodeWithSelector(IERC20.balanceOf.selector, alice), abi.encode(assets));

        uint256 totalSupply = iAsset.totalSupply();
        // Getting ZeroSharesAmount if bounded from 1
        assets = bound(assets, 2, totalSupply);
        vm.mockCall(
            address(iAsset),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, vault, assets),
            abi.encode(true)
        );

        uint256 oraclePrice = twoPriceOracle.price();

        vault.deposit(assets, alice, oraclePrice, bytes(""));
        uint256 availableReceiptBalance = receipt.balanceOf(alice, oraclePrice);
        checkBalanceChange(vault, alice, alice, oraclePrice, availableReceiptBalance, receipt, bytes(""));
    }
}
