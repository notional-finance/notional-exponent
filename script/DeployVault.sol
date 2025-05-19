// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import {TimelockUpgradeableProxy} from "../src/proxy/TimelockUpgradeableProxy.sol";
import {Initializable} from "../src/proxy/Initializable.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {MORPHO} from "../src/interfaces/Morpho/IMorpho.sol";
import {TRADING_MODULE} from "../src/interfaces/ITradingModule.sol";
import {MorphoLendingRouter} from "../src/routers/MorphoLendingRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV2V3Interface} from "../src/interfaces/AggregatorV2V3Interface.sol";
import {MockWrapperERC20, MockOracle, MockYieldStrategy} from "../tests/Mocks.sol";

// Vault: https://sepolia.etherscan.io/address/0xffd7531ed937f703b269815950cb75bdaaa341c9
abstract contract DeployVault is Script, GnosisHelper {
    TimelockUpgradeableProxy proxy;

    function deployVault() internal virtual returns (address impl);
    function postDeploySetup() internal virtual returns (MethodCall[] memory calls);

    function name() internal virtual returns (string memory);
    function symbol() internal virtual returns (string memory);

    function run() public {
        address impl = deployVault();
        console.log("Vault implementation deployed at", impl);

        vm.startBroadcast();
        proxy = new TimelockUpgradeableProxy(
            impl,
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(name(), symbol()))
        );
        vm.stopBroadcast();
        console.log("Vault proxy deployed at", address(proxy));

        postDeploySetup();
    }
}

contract DeployMockVault is DeployVault {
    address constant mockToken = 0xa40aedAac28F9574124D7c8EFf59732cC77f1DD4;
    MockWrapperERC20 w;
    MockOracle assetOracle;
    MockOracle wrapperOracle;
    MorphoLendingRouter lendingRouter = MorphoLendingRouter(0x280deCD520da16e5571A6f2Fb803A57e0c16f423);
    address constant IRM = 0x8C5dDCD3F601c91D1BF51c8ec26066010ACAbA7c;

    function name() internal override returns (string memory) {
        return "Mock Vault";
    }

    function symbol() internal override returns (string memory) {
        return "MOCK";
    }

    function deployVault() internal override returns (address impl) {
        vm.startBroadcast();
        w = new MockWrapperERC20(ERC20(mockToken));
        assetOracle = new MockOracle(1e18);
        wrapperOracle = new MockOracle(1e18);
        impl = address(new MockYieldStrategy(mockToken, address(w), 0.0010e18));
        vm.stopBroadcast();
    }

    function postDeploySetup() internal override returns (MethodCall[] memory calls) {
        vm.startBroadcast();
        TRADING_MODULE.setPriceOracle(mockToken, AggregatorV2V3Interface(address(assetOracle)));
        TRADING_MODULE.setPriceOracle(address(w), AggregatorV2V3Interface(address(wrapperOracle)));
        lendingRouter.initializeMarket(address(proxy), IRM, 0.915e18);

        ERC20(mockToken).approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(
            MorphoLendingRouter(address(lendingRouter)).marketParams(address(proxy)),
            1_000_000 * 10 ** ERC20(mockToken).decimals(), 0, msg.sender, ""
        );
        vm.stopBroadcast();
    }
}
