// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Simplified interface into a price oracle.
/// The intention is that some more complex oracle interface such as Chainlink
/// `AggregatorV3Interface` is wrapped/adapted by a contract that implements
/// `IPriceOracle` to produce a single final value.
///
/// Prices from an `IPriceOracle` MUST be:
/// - The latest available data/value
/// - Fresh enough or error if only too-stale data is available
/// - Represented as `uint256` values or error (e.g. disallow negative values)
/// - 18 decimal fixed point values representing a ratio (price) between "base"
/// and "quote" token.
///
/// By normalising all ratios to 18 decimal fixed point at their source we
/// simplify downstream math that derives prices by combining several
/// real price quotes.
///
/// If for any reason the underlying oracle cannot produce an appropriate
/// answer it MUST error rather than return inappropriate values. The ability
/// to do so MAY be limited by upstream providers (e.g. Chainlink silently
/// pausing price data during a heartbeat).
interface IPriceOracle {
    /// Returns the current/latest price according to the oracle.
    function price() external view returns (uint256);
}
