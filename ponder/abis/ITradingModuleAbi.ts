export const ITradingModuleAbi = [
  {
    type: "function",
    name: "canExecuteTrade",
    inputs: [
      {
        name: "from",
        type: "address",
        internalType: "address",
      },
      {
        name: "dexId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "trade",
        type: "tuple",
        internalType: "struct Trade",
        components: [
          {
            name: "tradeType",
            type: "uint8",
            internalType: "enum TradeType",
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "amount",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "limit",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "exchangeData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "executeTrade",
    inputs: [
      {
        name: "dexId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "trade",
        type: "tuple",
        internalType: "struct Trade",
        components: [
          {
            name: "tradeType",
            type: "uint8",
            internalType: "enum TradeType",
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "amount",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "limit",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "exchangeData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "amountSold",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "amountBought",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "executeTradeWithDynamicSlippage",
    inputs: [
      {
        name: "dexId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "trade",
        type: "tuple",
        internalType: "struct Trade",
        components: [
          {
            name: "tradeType",
            type: "uint8",
            internalType: "enum TradeType",
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "amount",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "limit",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "exchangeData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
      {
        name: "dynamicSlippageLimit",
        type: "uint32",
        internalType: "uint32",
      },
    ],
    outputs: [
      {
        name: "amountSold",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "amountBought",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "getExecutionData",
    inputs: [
      {
        name: "dexId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "from",
        type: "address",
        internalType: "address",
      },
      {
        name: "trade",
        type: "tuple",
        internalType: "struct Trade",
        components: [
          {
            name: "tradeType",
            type: "uint8",
            internalType: "enum TradeType",
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "amount",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "limit",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "exchangeData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
      {
        name: "target",
        type: "address",
        internalType: "address",
      },
      {
        name: "value",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "params",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getLimitAmount",
    inputs: [
      {
        name: "from",
        type: "address",
        internalType: "address",
      },
      {
        name: "tradeType",
        type: "uint8",
        internalType: "enum TradeType",
      },
      {
        name: "sellToken",
        type: "address",
        internalType: "address",
      },
      {
        name: "buyToken",
        type: "address",
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "slippageLimit",
        type: "uint32",
        internalType: "uint32",
      },
    ],
    outputs: [
      {
        name: "limitAmount",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getOraclePrice",
    inputs: [
      {
        name: "inToken",
        type: "address",
        internalType: "address",
      },
      {
        name: "outToken",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "answer",
        type: "int256",
        internalType: "int256",
      },
      {
        name: "decimals",
        type: "int256",
        internalType: "int256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "priceOracles",
    inputs: [
      {
        name: "token",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "oracle",
        type: "address",
        internalType: "contract AggregatorV2V3Interface",
      },
      {
        name: "rateDecimals",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "setMaxOracleFreshness",
    inputs: [
      {
        name: "newMaxOracleFreshnessInSeconds",
        type: "uint32",
        internalType: "uint32",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setPriceOracle",
    inputs: [
      {
        name: "token",
        type: "address",
        internalType: "address",
      },
      {
        name: "oracle",
        type: "address",
        internalType: "contract AggregatorV2V3Interface",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setTokenPermissions",
    inputs: [
      {
        name: "sender",
        type: "address",
        internalType: "address",
      },
      {
        name: "token",
        type: "address",
        internalType: "address",
      },
      {
        name: "permissions",
        type: "tuple",
        internalType: "struct ITradingModule.TokenPermissions",
        components: [
          {
            name: "allowSell",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "dexFlags",
            type: "uint32",
            internalType: "uint32",
          },
          {
            name: "tradeTypeFlags",
            type: "uint32",
            internalType: "uint32",
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "tokenWhitelist",
    inputs: [
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
      {
        name: "token",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "allowSell",
        type: "bool",
        internalType: "bool",
      },
      {
        name: "dexFlags",
        type: "uint32",
        internalType: "uint32",
      },
      {
        name: "tradeTypeFlags",
        type: "uint32",
        internalType: "uint32",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "MaxOracleFreshnessUpdated",
    inputs: [
      {
        name: "currentValue",
        type: "uint32",
        indexed: false,
        internalType: "uint32",
      },
      {
        name: "newValue",
        type: "uint32",
        indexed: false,
        internalType: "uint32",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PriceOracleUpdated",
    inputs: [
      {
        name: "token",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "oracle",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "TokenPermissionsUpdated",
    inputs: [
      {
        name: "sender",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "token",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "permissions",
        type: "tuple",
        indexed: false,
        internalType: "struct ITradingModule.TokenPermissions",
        components: [
          {
            name: "allowSell",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "dexFlags",
            type: "uint32",
            internalType: "uint32",
          },
          {
            name: "tradeTypeFlags",
            type: "uint32",
            internalType: "uint32",
          },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "TradeExecuted",
    inputs: [
      {
        name: "sellToken",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "buyToken",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "sellAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "buyAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
] as const;
