//+------------------------------------------------------------------+
//|                                                    Pro Forex.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Indicators/Indicators.mqh>
#include <Indicators/Trend.mqh>
#include <Indicators/Volumes.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input double risk_balance = 2; // The risk for each trade
input double max_spread_allowed = 2; // Maximum spread in pips above which the robot does not trade.
input int number_trades_per_day = 1; // Number of trades per day
input long magic_number = 55555; // Magic number
input bool use_auto_lots = true; // Calculate position size automatically

input int stop_loss_atr = 3; // The stop loss atr ratio
input int risk_reward = 2; // The risk reward ratio

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define TIMER_INTERVAL 10 // in seconds
#define MAX_POSITION_DURATION 10 // in the unit of current period

#define ATR_PERIOD 14

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
// Library
CTrade gTrade;
CIndicators gIndicators;

// Base timeframe
CiClose gCloseBtf;
CiOpen gOpenBtf;
CiLow gLowBtf;
CiHigh gHighBtf;

// Higher timeframe
CiClose gCloseHtf;
CiOpen gOpenHtf;
CiLow gLowHtf;
CiHigh gHighHtf;

// Indicators
CiATR gAtrBtf;

// Standard
string gSymbol;
ENUM_TIMEFRAMES gBaseTimeFrame;
ENUM_TIMEFRAMES gHigherTimeFrame;

// Trade management
double gTakeProfit;
double gStopLoss;

//+==================================================================+
//+========================== EXPERT ================================+
//+==================================================================+

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(TIMER_INTERVAL);

   gSymbol = _Symbol;
   gBaseTimeFrame = _Period;
   gHigherTimeFrame = HigherTimeFrame(_Period);
   gTrade.SetExpertMagicNumber(magic_number);

// Check the spread
   double symbolSpreadPoints = (double) SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);
   double symbolSpreadPips = symbolSpreadPoints / 10;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
     {
      // Spread value verification: the robot works only on currencies with low spread
      if(symbolSpreadPips > max_spread_allowed)
        {
         PrintFormat("The expert advisor can perform only when the spread is under %d pips.", max_spread_allowed);
         Print("The current spread is %d pips.", symbolSpreadPips);
         return(INIT_FAILED);
        }
     }

   bool setup = (
                   gCloseBtf.Create(gSymbol, gBaseTimeFrame)
                   && gOpenBtf.Create(gSymbol, gBaseTimeFrame)
                   && gLowBtf.Create(gSymbol, gBaseTimeFrame)
                   && gHighBtf.Create(gSymbol, gBaseTimeFrame)

                   && gCloseHtf.Create(gSymbol, gHigherTimeFrame)
                   && gOpenHtf.Create(gSymbol, gHigherTimeFrame)
                   && gLowHtf.Create(gSymbol, gHigherTimeFrame)
                   && gHighHtf.Create(gSymbol, gHigherTimeFrame)

                   && gIndicators.Add(&gCloseBtf)
                   && gIndicators.Add(&gOpenBtf)
                   && gIndicators.Add(&gLowBtf)
                   && gIndicators.Add(&gHighBtf)

                   && gIndicators.Add(&gCloseHtf)
                   && gIndicators.Add(&gOpenHtf)
                   && gIndicators.Add(&gLowHtf)
                   && gIndicators.Add(&gHighHtf)
                   
                   && gAtrBtf.Create(gSymbol, gBaseTimeFrame, ATR_PERIOD)
                   && gIndicators.Add(&gAtrBtf)
                );

   return(setup ? INIT_SUCCEEDED : INIT_FAILED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
// Only X trade(s) per day
   if(!CanStillTradeToday(number_trades_per_day))
      return;

// Time period filter
   if(!CanTradeNow())
      return;

// Do not trade if the spread is higher than the maximum spread allowed
   double symbolSpreadPoints = (double) SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);
   double symbolSpreadPips = symbolSpreadPoints / 10;
   if(symbolSpreadPips > max_spread_allowed)
      return;

// Process only when a new bar appears
   if(!IsNewBar())
      return;

   gIndicators.Refresh();
   PositionSelect(gSymbol);

// Wait until the position is closed
   if(PositionsTotal() > 0 || OrdersTotal() > 0)
      return;

   if(IsBuySignal(gSymbol))
     {
      double askPrice = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
      gStopLoss = askPrice - gAtrBtf.Main(1) * stop_loss_atr;
      gTakeProfit = askPrice + (askPrice - gStopLoss) * risk_reward;
      double stopLossPips = DifferenceInPips(askPrice, gStopLoss, gSymbol);
      double volume = use_auto_lots ? CalculateVolumeForTrade(gSymbol, risk_balance, stopLossPips) : CalculateLinearVolumeForTrade(gSymbol);
      gTrade.Buy(volume);
      return;
     }

   if(IsSellSignal(gSymbol))
     {
      double bidPrice = SymbolInfoDouble(gSymbol, SYMBOL_BID);
      gStopLoss = bidPrice + gAtrBtf.Main(1) * stop_loss_atr;
      gTakeProfit = bidPrice - (gStopLoss - bidPrice) * risk_reward;
      double stopLossPips = DifferenceInPips(bidPrice, gStopLoss, gSymbol); 
      double volume = use_auto_lots ? CalculateVolumeForTrade(gSymbol, risk_balance, stopLossPips) : CalculateLinearVolumeForTrade(gSymbol);
      gTrade.Sell(volume);
      return;
     }
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();

   if(PositionSelect(gSymbol))
     {
      long type = PositionGetInteger(POSITION_TYPE);

      // Check the TP and SL programmatically
      // if(ManageTpSl(type))
      //   return;

      datetime openTime = (datetime) PositionGetInteger(POSITION_TIME);

      // Close the position at the end of the Europe session
      if(IsEuropeSession(openTime) && !IsEuropeSession(now))
        {
         ClosePositions(gSymbol);
         return;
        }

      // Close the position at the end of the New York session
      if(IsNewYorkSession(openTime) && !IsNewYorkSession(now))
        {
         ClosePositions(gSymbol);
         return;
        }

      // Close the position after a certain of time
      datetime expiration = openTime + MAX_POSITION_DURATION * TimeFrameToSeconds(gBaseTimeFrame);
      if(TimeCurrent() > expiration)
        {
         ClosePositions(gSymbol);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if the position need to be close by TP or SL.              |
//+------------------------------------------------------------------+
bool ManageTpSl(long type)
  {
   if(gTakeProfit == 0 && gStopLoss == 0)
      return false;

// TP and SL for long position
   if(type == POSITION_TYPE_BUY && gStopLoss && gTakeProfit)
     {
      double bidPrice = SymbolInfoDouble(gSymbol, SYMBOL_BID);
      if(bidPrice >= gTakeProfit || bidPrice <= gStopLoss)
        {
         ClosePositions(gSymbol);
         return true;
        }
     }

// TP and SL for short position
   if(type == POSITION_TYPE_SELL && gStopLoss && gTakeProfit)
     {
      double askPrice = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
      if(askPrice <= gTakeProfit || askPrice >= gStopLoss)
        {
         ClosePositions(gSymbol);
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {

  }

//+==================================================================+
//+========================= STRATEGY ===============================+
//+==================================================================+

//+------------------------------------------------------------------+
//| The robot trade only on specifics period of time                 |
//+------------------------------------------------------------------+
bool CanTradeNow()
  {
   datetime now = TimeCurrent();
   return (IsEuropeSession(now) || IsNewYorkSession(now));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsEuropeSession(datetime time)
  {
   MqlDateTime date;
   TimeToStruct(time, date);
   return (date.hour >= 9 && date.hour < 12);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsNewYorkSession(datetime time)
  {
   MqlDateTime date;
   TimeToStruct(time, date);
   return (date.hour == 15 && date.min > 30) || (date.hour >= 16 && date.hour < 18) || (date.hour == 18 && date.min < 30);
  }

//+------------------------------------------------------------------+
//| Configure the robot to trade only X times per day                |
//+------------------------------------------------------------------+
bool CanStillTradeToday(int nbTradesPerDay = 1)
  {
   MqlDateTime today;
   datetime nullUhr;
   datetime now = TimeCurrent(today);
   int year = today.year;
   int month = today.mon;
   int day = today.day;
   nullUhr = StringToTime(string(year) + "." + string(month) + "." + string(day) + " 00:00");

   HistorySelect(nullUhr, now);
   int res = 0;

   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      datetime time = (datetime) HistoryDealGetInteger(ticket, DEAL_TIME);
      if(time > nullUhr)
        {
         res++;
         if(res == nbTradesPerDay)
            break;
        }
      else
         if(time < nullUhr)
            break;
     }

   return (res < nbTradesPerDay);
  }

//+------------------------------------------------------------------+
//| Return true if the conditions are met to buy                     |
//+------------------------------------------------------------------+
bool IsBuySignal(string pSymbol)
  {
   return false;
  }

//+------------------------------------------------------------------+
//| Return true if the conditions are met to sell                    |
//+------------------------------------------------------------------+
bool IsSellSignal(string pSymbol)
  {
   return false;
  }

//+------------------------------------------------------------------+
//| Check the trend to allow only long or short position             |
//+------------------------------------------------------------------+
int TrendFilter()
  {
   return 0;
  }

//+------------------------------------------------------------------+
//| Search for a particular volatility on the market to take position|
//+------------------------------------------------------------------+
bool VolatilityFilter()
  {
   return false;
  }

//+==================================================================+
//+=========================== UTILS ================================+
//+==================================================================+

//+------------------------------------------------------------------+
//| Close every open positions for a symbol                          |
//+------------------------------------------------------------------+
void ClosePositions(string pSymbol, ENUM_POSITION_TYPE pType = NULL)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == pSymbol && ((pType != NULL && PositionGetInteger(POSITION_TYPE) == pType) || pType == NULL))
            gTrade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Close every open orders for a symbol                             |
//+------------------------------------------------------------------+
void CloseOpenOrders(string pSymbol)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetString(ORDER_SYMBOL)== pSymbol)
            gTrade.OrderDelete(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Returns true if a new bar has appeared for a symbol/period pair  |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime priorTime = 0;
   datetime currentTime = iTime(Symbol(), Period(), 0);
   bool result = (currentTime != priorTime);
   priorTime = currentTime;
   return(result);
  }

//+------------------------------------------------------------------+
//| Calculate the lot size                                           |
//+------------------------------------------------------------------+
double CalculateLinearVolumeForTrade(string pSymbol)
  {
   double contractSize = SymbolInfoDouble(pSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lots = VerifyVolume(pSymbol, balance / (contractSize / 10));
   return(lots);
  }

//+------------------------------------------------------------------+
//| Calculate the lot size                                           |
//| @param pSymbol - The current symbol                              |
//| @param pPercent - The percent of balance to risk (0 - 1)         |
//| @param pStopLoss - The stop loss in pips                         |
//+------------------------------------------------------------------+
double CalculateVolumeForTrade(string pSymbol, double pPercent, double pStopLoss)
  {
   double tickValue = SymbolInfoDouble(pSymbol, SYMBOL_TRADE_TICK_VALUE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double risk = balance * pPercent;
   double lots = (risk / pStopLoss / tickValue) / 100;
   lots = VerifyVolume(pSymbol, lots);

   return(lots);
  }

//+------------------------------------------------------------------+
//| Verify the validity of the volume for a symbol                   |
//+------------------------------------------------------------------+
double VerifyVolume(string pSymbol, double pVolume)
  {
   double minVolume = SymbolInfoDouble(pSymbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(pSymbol, SYMBOL_VOLUME_MAX);
   double stepVolume = SymbolInfoDouble(pSymbol, SYMBOL_VOLUME_STEP);

   double volume;
   if(pVolume < minVolume)
      volume = minVolume;
   else
      if(pVolume > maxVolume)
         volume = maxVolume;
      else
         volume = MathRound(pVolume / stepVolume) * stepVolume;

   if(stepVolume >= 0.1)
      volume = NormalizeDouble(volume, 1);
   else
      volume = NormalizeDouble(volume, 2);

   return(volume);
  }

//+------------------------------------------------------------------+
//| Convert a price difference to pips                               |
//+------------------------------------------------------------------+
double DifferenceInPips(double pPrice1, double pPrice2, string pSymbol)
  {
   double point = SymbolInfoDouble(pSymbol, SYMBOL_POINT);
   double pip = point * 10;
   return MathAbs(pPrice1 - pPrice2) / pip;
  }

//+------------------------------------------------------------------+
//| Get the higher timeframe                                         |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES HigherTimeFrame(ENUM_TIMEFRAMES pTimeframe)
  {
   switch(pTimeframe)
     {
      case PERIOD_M1:
         return PERIOD_M15;
      case PERIOD_M2:
      case PERIOD_M3:
      case PERIOD_M4:
         return PERIOD_M30;
      case PERIOD_M5:
      case PERIOD_M6:
      case PERIOD_M10:
      case PERIOD_M12:
      case PERIOD_M15:
         return PERIOD_H1;
      case PERIOD_M20:
      case PERIOD_M30:
      case PERIOD_H1:
      case PERIOD_H2:
         return PERIOD_H4;
      case PERIOD_H3:
      case PERIOD_H4:
      case PERIOD_H6:
      case PERIOD_H8:
         return PERIOD_D1;
      default:
         return PERIOD_W1;
     }
  }

//+------------------------------------------------------------------+
//| Returns the seconds for a timeframe                              |
//+------------------------------------------------------------------+
int TimeFrameToSeconds(ENUM_TIMEFRAMES pTimeFrame)
  {
   switch(pTimeFrame)
     {
      case PERIOD_M1:
         return 60;
      case PERIOD_M2:
         return 60 * 2;
      case PERIOD_M3:
         return 60 * 3;
      case PERIOD_M4:
         return 60 * 4;
      case PERIOD_M5:
         return 60 * 5;
      case PERIOD_M6:
         return 60 * 6;
      case PERIOD_M10:
         return 60 * 10;
      case PERIOD_M12:
         return 60 * 12;
      case PERIOD_M15:
         return 60 * 15;
      case PERIOD_M20:
         return 60 * 20;
      case PERIOD_M30:
         return 60 * 30;
      case PERIOD_H1:
         return 3600;
      case PERIOD_H2:
         return 3600 * 2;
      case PERIOD_H3:
         return 3600 * 3;
      case PERIOD_H4:
         return 3600 * 4;
      case PERIOD_H6:
         return 3600 * 6;
      case PERIOD_H8:
         return 3600 * 8;
      case PERIOD_D1:
         return 3600 * 24;
      case PERIOD_W1:
         return 3600 * 24 * 7;
      default:
         return -1;
     }
  }

//+==================================================================+
//+======================= CANDLE UTILS =============================+
//+==================================================================+

//+------------------------------------------------------------------+
//| Get the higher high from the X last candles                      |
//+------------------------------------------------------------------+
double Higher(int count = 0)
  {
   double max = gHighBtf.GetData(0);
   for(int i = 1; i <= count; i++)
     {
      if(gHighBtf.GetData(i) > max)
         max = gHighBtf.GetData(i);
     }
   return max;
  }

//+------------------------------------------------------------------+
//| Get the lower low from the X last candles                        |
//+------------------------------------------------------------------+
double Lower(int count = 0)
  {
   double min = gLowBtf.GetData(0);
   for(int i = 1; i <= count; i++)
     {
      if(gHighBtf.GetData(i) < min)
         min = gLowBtf.GetData(i);
     }
   return min;
  }

//+==================================================================+
//+=============== CANDLE PATTERN DETECTION =========================+
//+==================================================================+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsWhiteCandle(double o, double c)
  {
   return o < c;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsBlackCandle(double o, double c)
  {
   return o > c;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(double h1, double o1, double l1, double c1, double h2, double o2, double l2, double c2)
  {
   return l1 < l2 && h1 > h2 && c1 > c2 && o1 < o2;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(double h1, double o1, double l1, double c1, double h2, double o2, double l2, double c2)
  {
   return l1 < l2 && h1 > h2 && c1 < c2 && o1 > o2;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsBullishPinBar(double h, double o, double l, double c)
  {
   return (h - l) > 3 * MathAbs(c - o) && (h - o) < 0.3 * (h - l) && c > o;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsBearishPinBar(double h, double o, double l, double c)
  {
   return (h - l) > 3 * MathAbs(c - o) && (o - l) < 0.3 * (h - l) && c < o;
  }

//+------------------------------------------------------------------+
