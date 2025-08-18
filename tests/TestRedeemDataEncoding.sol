// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "../src/interfaces/ITradingModule.sol";

contract TestRedeemDataEncoding is Test {
    
    function test_RedeemDataEncoding() public pure {
        // This matches the exact encoding from TestMockStakingStrategy_EtherFi
        bytes memory redeemData = abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.CURVE_V2), // Should be 7
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                fromIndex: 1,
                toIndex: 0
            }))
        }));
        
        console.log("Solidity encoded RedeemParams:");
        console.logBytes(redeemData);
        
        // Also test the CurveV2SingleData separately
        bytes memory curveData = abi.encode(CurveV2SingleData({
            pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
            fromIndex: 1,
            toIndex: 0
        }));
        
        console.log("Solidity encoded CurveV2SingleData:");
        console.logBytes(curveData);
        
        // Verify DexId.CURVE_V2 value
        console.log("DexId.CURVE_V2 value:", uint8(DexId.CURVE_V2));
    }
    
    function test_RedeemDataEncodingWithAmount() public pure {
        // Test with non-zero min purchase amount (1 ether)
        bytes memory redeemData = abi.encode(RedeemParams({
            minPurchaseAmount: 1 ether,
            dexId: uint8(DexId.CURVE_V2),
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                fromIndex: 1,
                toIndex: 0
            }))
        }));
        
        console.log("Solidity encoded RedeemParams with 1 ether min:");
        console.logBytes(redeemData);
    }
}