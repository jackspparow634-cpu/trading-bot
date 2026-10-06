//+------------------------------------------------------------------+
//|                 Ultra_Gold_Advanced_EA_v4_1.mq5                 |
//|                       Waqas Trading                              |
//+------------------------------------------------------------------+
#property copyright "Waqas Trading"
#property version   "4.10"
#property strict

//====================================================================
// GENERAL
//====================================================================

input group "===== GENERAL ====="
input ulong    InpMagicNumber           = 99999;
input double   InpFixedLot              = 0.01;
input bool     InpUseRiskPercent        = true;
input double   InpRiskPercent           = 1.0;
input int      InpMaxSpreadPoints       = 35;
input int      InpSlippagePoints        = 20;

//====================================================================
// TIME FILTER
//====================================================================

input group "===== TIME FILTER ====="
input bool     InpUseTimeFilter         = true;
input int      InpStartHour             = 10;
input int      InpEndHour               = 21;

//====================================================================
// TREND FILTER
//====================================================================

input group "===== TREND FILTER ====="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;
input int      InpFastEMA               = 9;
input int      InpSlowEMA               = 21;
input int      InpTrendEMA              = 50;

//====================================================================
// RSI
//====================================================================

input group "===== RSI FILTER ====="
input int      InpRSIPeriod             = 14;
input double   InpRSIBuyLevel            = 35.0;
input double   InpRSISellLevel           = 65.0;

//====================================================================
// ATR
//====================================================================

input group "===== ATR / VOLATILITY ====="
input int      InpATRPeriod             = 14;
input double   InpMinATR                = 0.50;
input double   InpSL_ATR_Multiplier     = 1.8;
input double   InpTP_ATR_Multiplier     = 3.0;

//====================================================================
// BREAK EVEN
//====================================================================

input group "===== BREAK EVEN ====="
input bool     InpUseBreakEven          = true;
input double   InpBE_ATR_Multiplier     = 1.0;
input double   InpBE_LockPoints         = 100;

//====================================================================
// TRAILING
//====================================================================

input group "===== TRAILING ====="
input bool     InpUseTrailing           = true;
input double   InpTrailStartATR         = 1.5;
input double   InpTrailDistanceATR      = 1.0;

//====================================================================
// TRADE LIMITS
//====================================================================

input group "===== TRADE LIMITS ====="
input int      InpMaxTradesPerDay       = 3;
input int      InpCooldownMinutes       = 30;
input int      InpMaxConsecutiveLosses  = 3;

//====================================================================
// CANDLE CONFIRMATION
//====================================================================

input group "===== CANDLE CONFIRMATION ====="
input bool     InpUseCandleConfirmation = true;
input double   InpMinBodyPercent        = 55.0;

//====================================================================
// INDICATOR HANDLES
//====================================================================

int rsiHandle       = INVALID_HANDLE;
int fastEMAHandle   = INVALID_HANDLE;
int slowEMAHandle   = INVALID_HANDLE;
int trendEMAHandle  = INVALID_HANDLE;
int atrHandle       = INVALID_HANDLE;

datetime lastBarTime   = 0;
datetime lastTradeTime = 0;

//====================================================================
// INITIALIZATION
//====================================================================

int OnInit()
{
   rsiHandle =
      iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);

   fastEMAHandle =
      iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

   slowEMAHandle =
      iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   trendEMAHandle =
      iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   atrHandle =
      iATR(_Symbol, _Period, InpATRPeriod);

   if(rsiHandle == INVALID_HANDLE ||
      fastEMAHandle == INVALID_HANDLE ||
      slowEMAHandle == INVALID_HANDLE ||
      trendEMAHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Indicator initialization failed.");
      return INIT_FAILED;
   }

   Print("Ultra Gold Advanced EA v4.1 initialized successfully.");

   return INIT_SUCCEEDED;
}

//====================================================================
// DEINITIALIZATION
//====================================================================

void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);

   if(fastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(fastEMAHandle);

   if(slowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(slowEMAHandle);

   if(trendEMAHandle != INVALID_HANDLE)
      IndicatorRelease(trendEMAHandle);

   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}

//====================================================================
// MAIN TICK
//====================================================================

void OnTick()
{
   // Manage existing trades on every tick
   ManagePositions();

   // New entries only once per candle
   if(!IsNewBar())
      return;

   // Spread protection
   if(!SpreadOK())
      return;

   // Time protection
   if(!TradingTimeOK())
      return;

   // Don't open another EA position
   if(HasOurPosition())
      return;

   // Daily trade limit
   if(GetTodayTradeCount() >= InpMaxTradesPerDay)
      return;

   // Consecutive loss protection
   if(GetConsecutiveLosses() >= InpMaxConsecutiveLosses)
      return;

   // Cooldown protection
   if(lastTradeTime > 0)
   {
      if((TimeCurrent() - lastTradeTime) <
         InpCooldownMinutes * 60)
      {
         return;
      }
   }

   CheckForEntry();
}

//====================================================================
// NEW BAR
//====================================================================

bool IsNewBar()
{
   datetime currentBarTime =
      iTime(_Symbol, _Period, 0);

   if(currentBarTime == 0)
      return false;

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//====================================================================
// SPREAD
//====================================================================

bool SpreadOK()
{
   double ask =
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double bid =
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double spreadPoints =
      (ask - bid) / _Point;

   if(spreadPoints > InpMaxSpreadPoints)
   {
      Print("Spread too high: ",
            DoubleToString(spreadPoints, 1),
            " points");

      return false;
   }

   return true;
}

//====================================================================
// TIME FILTER
//====================================================================

bool TradingTimeOK()
{
   if(!InpUseTimeFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Normal session
   if(InpStartHour <= InpEndHour)
   {
      if(dt.hour < InpStartHour ||
         dt.hour >= InpEndHour)
      {
         return false;
      }
   }
   else
   {
      // Overnight session
      if(dt.hour >= InpEndHour &&
         dt.hour < InpStartHour)
      {
         return false;
      }
   }

   return true;
}

//====================================================================
// ENTRY CHECK
//====================================================================

void CheckForEntry()
{
   // IMPORTANT:
   // Dynamic arrays are used here.
   // This fixes the "static allocated array" warnings.

   double rsi[];
   double fastEMA[];
   double slowEMA[];
   double atr[];
   double trendEMA[];

   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(trendEMA, true);

   if(CopyBuffer(rsiHandle, 0, 1, 2, rsi) < 2)
      return;

   if(CopyBuffer(fastEMAHandle, 0, 1, 2, fastEMA) < 2)
      return;

   if(CopyBuffer(slowEMAHandle, 0, 1, 2, slowEMA) < 2)
      return;

   if(CopyBuffer(atrHandle, 0, 1, 2, atr) < 2)
      return;

   if(CopyBuffer(trendEMAHandle, 0, 1, 2, trendEMA) < 2)
      return;

   // Closed candle
   double close1 =
      iClose(_Symbol, _Period, 1);

   double open1 =
      iOpen(_Symbol, _Period, 1);

   double high1 =
      iHigh(_Symbol, _Period, 1);

   double low1 =
      iLow(_Symbol, _Period, 1);

   if(close1 <= 0.0 ||
      atr[0] <= 0.0)
   {
      return;
   }

   //==============================================================
   // ATR FILTER
   //==============================================================

   if(atr[0] < InpMinATR)
   {
      Print("ATR too low. No trade.");
      return;
   }

   //==============================================================
   // HIGHER TIMEFRAME TREND
   //==============================================================

   double trendClose =
      iClose(_Symbol, InpTrendTF, 1);

   if(trendClose <= 0.0)
      return;

   bool higherTFBull =
      trendClose > trendEMA[0];

   bool higherTFBear =
      trendClose < trendEMA[0];

   //==============================================================
   // LOCAL TREND
   //==============================================================

   bool localBull =
      fastEMA[0] > slowEMA[0];

   bool localBear =
      fastEMA[0] < slowEMA[0];

   //==============================================================
   // CANDLE CONFIRMATION
   //==============================================================

   bool bullishCandle = true;
   bool bearishCandle = true;

   if(InpUseCandleConfirmation)
   {
      double range =
         high1 - low1;

      if(range <= 0.0)
         return;

      double body =
         MathAbs(close1 - open1);

      double bodyPercent =
         (body / range) * 100.0;

      bullishCandle =
         close1 > open1 &&
         bodyPercent >= InpMinBodyPercent;

      bearishCandle =
         close1 < open1 &&
         bodyPercent >= InpMinBodyPercent;
   }

   //==============================================================
   // BUY SIGNAL
   //==============================================================

   bool buySignal =
      localBull &&
      higherTFBull &&
      rsi[0] <= InpRSIBuyLevel &&
      bullishCandle;

   //==============================================================
   // SELL SIGNAL
   //==============================================================

   bool sellSignal =
      localBear &&
      higherTFBear &&
      rsi[0] >= InpRSISellLevel &&
      bearishCandle;

   if(buySignal)
   {
      OpenTrade(ORDER_TYPE_BUY, atr[0]);
   }
   else if(sellSignal)
   {
      OpenTrade(ORDER_TYPE_SELL, atr[0]);
   }
}

//====================================================================
// OPEN TRADE
//====================================================================

void OpenTrade(
   ENUM_ORDER_TYPE type,
   double atrValue)
{
   double ask =
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double bid =
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0.0 || bid <= 0.0)
      return;

   double price;

   if(type == ORDER_TYPE_BUY)
      price = ask;
   else
      price = bid;

   // ATR based SL / TP
   double slDistance =
      atrValue * InpSL_ATR_Multiplier;

   double tpDistance =
      atrValue * InpTP_ATR_Multiplier;

   if(slDistance <= 0.0 ||
      tpDistance <= 0.0)
   {
      return;
   }

   double sl;
   double tp;

   if(type == ORDER_TYPE_BUY)
   {
      sl = price - slDistance;
      tp = price + tpDistance;
   }
   else
   {
      sl = price + slDistance;
      tp = price - tpDistance;
   }

   // Broker minimum stop distance
   long stopLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL);

   double minDistance =
      (double)stopLevel * _Point;

   if(minDistance > 0.0)
   {
      if(type == ORDER_TYPE_BUY)
      {
         if(price - sl < minDistance)
            sl = price - minDistance;

         if(tp - price < minDistance)
            tp = price + minDistance;
      }
      else
      {
         if(sl - price < minDistance)
            sl = price + minDistance;

         if(price - tp < minDistance)
            tp = price - minDistance;
      }
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Lot calculation
   double lot =
      CalculateLotSize(
         MathAbs(price - sl));

   if(lot <= 0.0)
   {
      Print("Invalid lot size.");
      return;
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action =
      TRADE_ACTION_DEAL;

   request.symbol =
      _Symbol;

   request.magic =
      InpMagicNumber;

   request.volume =
      lot;

   request.type =
      type;

   request.price =
      price;

   request.sl =
      sl;

   request.tp =
      tp;

   request.deviation =
      InpSlippagePoints;

   request.type_filling =
      GetFillingMode();

   ResetLastError();

   bool sent =
      OrderSend(request, result);

   if(!sent)
   {
      Print("OrderSend failed. Error: ",
            GetLastError());

      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Trade rejected. Retcode: ",
            result.retcode,
            " Comment: ",
            result.comment);

      return;
   }

   lastTradeTime =
      TimeCurrent();

   Print(
      "TRADE OPENED | ",
      "Type=", EnumToString(type),
      " | Lot=", DoubleToString(lot, 2),
      " | SL=", DoubleToString(sl, _Digits),
      " | TP=", DoubleToString(tp, _Digits)
   );
}

//====================================================================
// LOT SIZE
//====================================================================

double CalculateLotSize(
   double slDistance)
{
   if(!InpUseRiskPercent)
      return NormalizeLot(InpFixedLot);

   if(slDistance <= 0.0)
      return 0.0;

   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE);

   double riskMoney =
      balance *
      (InpRiskPercent / 100.0);

   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 ||
      tickValue <= 0.0)
   {
      return NormalizeLot(InpFixedLot);
   }

   double lossPerLot =
      (slDistance / tickSize) *
      tickValue;

   if(lossPerLot <= 0.0)
      return 0.0;

   double lot =
      riskMoney / lossPerLot;

   return NormalizeLot(lot);
}

//====================================================================
// NORMALIZE LOT
//====================================================================

double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   lot =
      MathMax(minLot, lot);

   lot =
      MathMin(maxLot, lot);

   lot =
      MathFloor(lot / step) * step;

   int digits = 2;

   if(step >= 1.0)
      digits = 0;
   else if(step >= 0.1)
      digits = 1;

   return NormalizeDouble(
      lot,
      digits);
}

//====================================================================
// FILLING MODE
//====================================================================

ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   long filling =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

//====================================================================
// OUR POSITION CHECK
//====================================================================

bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL);

      long magic =
         PositionGetInteger(
            POSITION_MAGIC);

      if(symbol == _Symbol &&
         magic == (long)InpMagicNumber)
      {
         return true;
      }
   }

   return false;
}

//====================================================================
// MANAGE ALL POSITIONS
//====================================================================

void ManagePositions()
{
   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL);

      long magic =
         PositionGetInteger(
            POSITION_MAGIC);

      if(symbol != _Symbol ||
         magic != (long)InpMagicNumber)
      {
         continue;
      }

      ManageSinglePosition(ticket);
   }
}

//====================================================================
// MANAGE ONE POSITION
//====================================================================

void ManageSinglePosition(
   ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   long type =
      PositionGetInteger(
         POSITION_TYPE);

   double openPrice =
      PositionGetDouble(
         POSITION_PRICE_OPEN);

   double currentSL =
      PositionGetDouble(
         POSITION_SL);

   double currentTP =
      PositionGetDouble(
         POSITION_TP);

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   if(bid <= 0.0 || ask <= 0.0)
      return;

   double currentPrice;

   if(type == POSITION_TYPE_BUY)
      currentPrice = bid;
   else
      currentPrice = ask;

   // Dynamic ATR array
   double atr[];

   ArraySetAsSeries(atr, true);

   if(CopyBuffer(
         atrHandle,
         0,
         0,
         1,
         atr) < 1)
   {
      return;
   }

   double atrValue = atr[0];

   if(atrValue <= 0.0)
      return;

   double profitDistance;

   if(type == POSITION_TYPE_BUY)
      profitDistance =
         currentPrice - openPrice;
   else
      profitDistance =
         openPrice - currentPrice;

   //==============================================================
   // BREAK EVEN
   //==============================================================

   if(InpUseBreakEven &&
      profitDistance >=
      atrValue * InpBE_ATR_Multiplier)
   {
      double newSL;

      if(type == POSITION_TYPE_BUY)
      {
         newSL =
            openPrice +
            InpBE_LockPoints * _Point;

         newSL =
            NormalizeDouble(
               newSL,
               _Digits);

         if(currentSL == 0.0 ||
            newSL > currentSL)
         {
            ModifyPosition(
               ticket,
               newSL,
               currentTP);
         }
      }
      else
      {
         newSL =
            openPrice -
            InpBE_LockPoints * _Point;

         newSL =
            NormalizeDouble(
               newSL,
               _Digits);

         if(currentSL == 0.0 ||
            newSL < currentSL)
         {
            ModifyPosition(
               ticket,
               newSL,
               currentTP);
         }
      }
   }

   //==============================================================
   // ATR TRAILING
   //==============================================================

   if(InpUseTrailing &&
      profitDistance >=
      atrValue * InpTrailStartATR)
   {
      double newSL;

      if(type == POSITION_TYPE_BUY)
      {
         newSL =
            currentPrice -
            atrValue *
            InpTrailDistanceATR;

         newSL =
            NormalizeDouble(
               newSL,
               _Digits);

         if(currentSL == 0.0 ||
            newSL > currentSL)
         {
            ModifyPosition(
               ticket,
               newSL,
               currentTP);
         }
      }
      else
      {
         newSL =
            currentPrice +
            atrValue *
            InpTrailDistanceATR;

         newSL =
            NormalizeDouble(
               newSL,
               _Digits);

         if(currentSL == 0.0 ||
            newSL < currentSL)
         {
            ModifyPosition(
               ticket,
               newSL,
               currentTP);
         }
      }
   }
}

//====================================================================
// MODIFY POSITION
//====================================================================

void ModifyPosition(
   ulong ticket,
   double newSL,
   double currentTP)
{
   if(!PositionSelectByTicket(ticket))
      return;

   long type =
      PositionGetInteger(
         POSITION_TYPE);

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   long stopLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL);

   double minDistance =
      (double)stopLevel * _Point;

   if(type == POSITION_TYPE_BUY)
   {
      if(bid - newSL < minDistance)
         return;
   }
   else
   {
      if(newSL - ask < minDistance)
         return;
   }

   newSL =
      NormalizeDouble(
         newSL,
         _Digits);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action =
      TRADE_ACTION_SLTP;

   request.symbol =
      _Symbol;

   request.position =
      ticket;

   request.sl =
      newSL;

   request.tp =
      currentTP;

   ResetLastError();

   bool sent =
      OrderSend(request, result);

   if(!sent)
   {
      Print(
         "SL modification failed. Error: ",
         GetLastError());

      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print(
         "SL modification rejected: ",
         result.retcode,
         " ",
         result.comment);
   }
}

//====================================================================
// TODAY'S TRADE COUNT
//====================================================================

int GetTodayTradeCount()
{
   datetime now =
      TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime startOfDay =
      StructToTime(dt);

   if(!HistorySelect(
         startOfDay,
         now))
   {
      return 0;
   }

   int count = 0;

   int total =
      HistoryDealsTotal();

   for(int i = 0;
       i < total;
       i++)
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);

      if(dealTicket == 0)
         continue;

      string symbol =
         HistoryDealGetString(
            dealTicket,
            DEAL_SYMBOL);

      long magic =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_MAGIC);

      long entry =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_ENTRY);

      if(symbol == _Symbol &&
         magic == (long)InpMagicNumber &&
         entry == DEAL_ENTRY_IN)
      {
         count++;
      }
   }

   return count;
}

//====================================================================
// CONSECUTIVE LOSSES
//====================================================================

int GetConsecutiveLosses()
{
   datetime now =
      TimeCurrent();

   if(!HistorySelect(
         0,
         now))
   {
      return 0;
   }

   int losses = 0;

   int total =
      HistoryDealsTotal();

   for(int i = total - 1;
       i >= 0;
       i--)
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);

      if(dealTicket == 0)
         continue;

      string symbol =
         HistoryDealGetString(
            dealTicket,
            DEAL_SYMBOL);

      long magic =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_MAGIC);

      long entry =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_ENTRY);

      if(symbol != _Symbol ||
         magic != (long)InpMagicNumber ||
         entry != DEAL_ENTRY_OUT)
      {
         continue;
      }

      double profit =
         HistoryDealGetDouble(
            dealTicket,
            DEAL_PROFIT);

      if(profit < 0.0)
      {
         losses++;
      }
      else if(profit > 0.0)
      {
         break;
      }
   }

   return losses;
}

//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
