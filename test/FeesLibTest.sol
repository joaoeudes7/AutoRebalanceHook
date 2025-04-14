// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FeesLib} from "../src/libraries/FeesLib.sol";

contract FeesLibTest is Test {
    function setUp() public {
        // No setup needed for testing pure functions
    }

    /*//////////////////////////////////////////////////////////////
                     REINVESTMENT WORTHWHILE TESTS
    //////////////////////////////////////////////////////////////*/

    function testIsReinvestmentWorthwhile_BothZero() public pure {
        uint256 amount0 = 0;
        uint256 amount1 = 0;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertFalse(result, "Reinvestment should not be worthwhile with zero fees");
    }

    function testIsReinvestmentWorthwhile_BelowMinToken1() public pure {
        uint256 amount0 = 0;
        uint256 amount1 = 50;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertFalse(result, "Reinvestment should not be worthwhile when below minimum amount");
    }

    function testIsReinvestmentWorthwhile_AboveMinToken1() public pure {
        uint256 amount0 = 0;
        uint256 amount1 = 150;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertTrue(result, "Reinvestment should be worthwhile when above minimum amount");
    }

    function testIsReinvestmentWorthwhile_BelowMinToken0() public pure {
        uint256 amount0 = 50;
        uint256 amount1 = 0;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertFalse(result, "Reinvestment should not be worthwhile when token0 converted is below minimum");
    }

    function testIsReinvestmentWorthwhile_AboveMinToken0() public pure {
        uint256 amount0 = 150;
        uint256 amount1 = 0;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertTrue(result, "Reinvestment should be worthwhile when token0 converted is above minimum");
    }

    function testIsReinvestmentWorthwhile_CombinedAmount() public pure {
        uint256 amount0 = 60;
        uint256 amount1 = 50;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format

        // With price 1.0, the combined value should be 50 + 60 = 110, which is above the minimum
        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        assertTrue(result, "Reinvestment should be worthwhile when combined tokens are above minimum");
    }

    function testIsReinvestmentWorthwhile_PriceImpact() public pure {
        uint256 amount0 = 100;
        uint256 amount1 = 0;
        uint256 minAmount = 100;

        // Test with different price values
        uint160 price1 = 79228162514264337593543950336; // 1.0 in Q64.96 format
        uint160 price2 = 158456325028528675187087900672; // 2.0 in Q64.96 format
        uint160 price3 = 39614081257132168796771975168; // 0.5 in Q64.96 format

        bool result1 = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price1);
        bool result2 = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price2);
        bool result3 = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price3);

        // With 100 amount0:
        // At price 1.0: value = 100 (equal to minimum)
        // At price 2.0: value = 200 (above minimum)
        // At price 0.5: value = 50 (below minimum)
        assertTrue(result1, "At price 1.0, reinvestment should be worthwhile");
        assertTrue(result2, "At price 2.0, reinvestment should be worthwhile");
        assertFalse(result3, "At price 0.5, reinvestment should not be worthwhile");
    }

    /*//////////////////////////////////////////////////////////////
                  CALCULATE LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCalculateLiquidityForAmounts() public pure {
        int24 lowerTick = -100;
        int24 upperTick = 100;
        uint256 amount0 = 1 ether;
        uint256 amount1 = 1 ether;

        uint128 liquidity = FeesLib.calculateLiquidityForAmounts(lowerTick, upperTick, amount0, amount1);

        // Currently, the implementation returns 0 as a placeholder
        assertEq(liquidity, 0, "Liquidity calculation should return the placeholder value");
    }

    /*//////////////////////////////////////////////////////////////
                     FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_IsReinvestmentWorthwhile(uint256 amount0, uint256 amount1, uint256 minAmount, uint160 price)
        public
        pure
    {
        // Constrain values to reasonable bounds
        amount0 = bound(amount0, 0, 1e18);
        amount1 = bound(amount1, 0, 1e18);
        minAmount = bound(minAmount, 1, 1e18);

        // Ensure price is not 0 and is within reasonable bounds
        price = uint160(bound(uint256(price), 1, type(uint160).max));

        bool result = FeesLib.isReinvestmentWorthwhile(amount0, amount1, minAmount, price);

        // If both amounts are 0, result should be false
        if (amount0 == 0 && amount1 == 0) {
            assertFalse(result, "Result should be false when both amounts are 0");
        }
        // If amount1 >= minAmount, result should be true
        else if (amount1 >= minAmount) {
            assertTrue(result, "Result should be true when amount1 >= minAmount");
        }
        // For other cases, we can't make absolute assertions due to price complexity
    }
}
