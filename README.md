# BitcoinCore.Swift
BitcoinCore for Bitcoin, BitcoinCash(ABC), Litecoin and Dash wallet toolkit for Swift. This is a full implementation of SPV node including wallet creation/restore, synchronization with network, send/receive transactions, and more.


## Features

- Full SPV implementation for fast mobile performance
- Send/Receive Legacy transactions (*P2PKH*, *P2PK*, *P2SH*)
- [BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki) hierarchical deterministic wallets implementation.
- [BIP39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) mnemonic code for generating deterministic keys.
- [BIP44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki) multi-account hierarchy for deterministic wallets.
- [BIP21](https://github.com/bitcoin/bips/blob/master/bip-0021.mediawiki) URI schemes, which include payment address, amount, label and other params

### Initialization

Core must be used by concrete Kit, i.e. BitcoinKit.Swift, DashKit.swift...

## Prerequisites

* Xcode 10.0+
* Swift 5+
* iOS 13+

## Installation
To run tests you need make cuckoo generator using instructions from https://github.com/Brightify/Cuckoo

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code
and is integrated into the `swift` compiler. It is in early development, but HdWalletKit does support its use on
supported platforms.

Once you have your Swift package set up, adding HdWalletKit as a dependency is as easy as adding it to
the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/horizontalsystems/BitcoinCore.Swift.git", .upToNextMajor(from: "1.0.0"))
]
```

## License

The `BitcoinCore.Swift` toolkit is open source and available under the terms of the [MIT License](https://github.com/horizontalsystems/BitcoinCore.Swift/blob/master/LICENSE).

