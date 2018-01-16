//
//  CurrenciesStore.swift
//  BTCMarkets
//
//  Created by Stephen Yao on 15/1/18.
//  Copyright © 2018 Stephen Yao. All rights reserved.
//

import Foundation
import PromiseKit
import SocketIO

final class CoinsStoreAud: CoinsStore {
  static var sharedInstance: CoinsStoreAud = CoinsStoreAud()

  override var currency: Currency! {
    return .aud
  }
}

final class CoinsStoreBtc: CoinsStore {
  static var sharedInstance: CoinsStoreBtc = CoinsStoreBtc()
  
  override var currency: Currency! {
    return .btc
  }
}

class CoinsStore: CurrencyFetcher {
  typealias CurrencyCoins = [Currency: Coin]
  typealias Subscriber = String
  typealias CurrencyCoinsChanged = (CurrencyCoins) -> Void
  
  private var subscribers: [(Subscriber, CurrencyCoinsChanged)] = []
  private var currencyCoins: CurrencyCoins = CurrencyCoins()
  
  // Abstract implementation. Must override.
  var currency: Currency! {
    return nil
  }

  private var socketManager: SocketManager = SocketManager(socketURL: URL(string: "https://socket.btcmarkets.net")!,  config: [.compress, .secure(true), .forceWebsockets(true)])
  private var socket: SocketIOClient?
  
  init() {
    self.socket = socketManager.defaultSocket
  }
  
  func coin(forCurrency currency: Currency) -> Coin? {
    return currencyCoins[currency]
  }
  
  func start() {
    let promises = Currency.allExceptAud.map { fetchCurrency(currency: currency, instrument: $0) }
    
    promises.forEach { promise in
      promise.then { coin -> Void in
        guard let coin = coin, let currency = Currency(rawValue: coin.instrument) else {
          return
        }
        
        self.currencyCoins[currency] = coin
        self.setupSocket(currency: self.currency)
      }.catch { error in print(error) }
    }
  }
  
  private func setupSocket(currency: Currency) {
    let instruments = Currency.allExceptAud
    
    socket?.on(clientEvent: .connect) { [weak self] data, ack in
      instruments.forEach { instrument in
        let channelName = "Ticker-BTCMarkets-\(instrument.rawValue)-\(currency.rawValue)"
        self?.socket?.emit("join", with: [channelName])
      }
    }
    
    socket?.on("newTicker") { [weak self] data, ack in
      guard let strongSelf = self,
        let json = data.first as? JSONResponse,
        var coin = Coin(JSON: json),
        let currency = Currency(rawValue: coin.instrument) else {
          return
      }
      
      coin.normaliseValues()
      strongSelf.currencyCoins[currency] = coin
      strongSelf.subscribers.forEach { $0.1(strongSelf.currencyCoins) }
    }
    
    socket?.connect()
  }
  
  func subscribe(subscriber: Subscriber, callback: @escaping CurrencyCoinsChanged) {
    subscribers.append((subscriber, callback))
    callback(currencyCoins)
  }
  
  func unsubscribe(subscriber: Subscriber) {
    if let subscriberIndex = (subscribers.index { return $0.0 == subscriber }) {
      subscribers.remove(at: subscriberIndex)
    }
  }
}
