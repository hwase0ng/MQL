//+--------------------------------------------------------+
//| G#MACD_Divergence_EA.mq4
//| Copyright © 2013, roysten
//+--------------------------------------------------------+
// Structure #1 (Optional): Directives
#property copyright "Copyright © 2013, roysten.tan@gmail.com"
#include <stderror.mqh>
#include <stdlib.mqh>

// Structure #2 (Optional): Input parameters

extern string EAName = "EA8033";
extern double MagicNumber = 8033;
extern int TimeFrame = 240;

//extern bool MM = TRUE;
extern int ConcurrentOrders = 3;
extern double RiskRatio = 2;
extern int MinPips = 1;
extern int MaxPips = 20;
extern double LotDigits =2;
extern int TakeProfit = 0;
extern int StopLossBarCount = 1;
extern int StopLossTolerancePc = 0;

extern double TrailingStart = 50;
extern double TrailingStop  = 25;
extern double TrailingStep  = 5; 

extern int Slippage = 5;
extern bool ForceOppositeClose=false;
extern bool OppositeClose = true;
extern bool EnterOpenBar = true;
extern bool AdjustStop = true;
extern bool MatchLastOrder = true;
//---- MA Filter input parameters
extern string separator1 = "*** MA Filter Settings ***";
//extern bool MAFilter=false;
//extern bool MAFilterRev = false;
//extern int MATime = 0;
//extern int MAPeriod = 50;
//extern int MAMethod=1;
//extern int MAShift=1;

extern int FastMATime = 0;
extern int FastMAPeriod = 8;
extern int FastMAType = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FastMAPrice = 0;
extern int FastMAShift = 0;
//---------------------
extern int MidMATime = 0;
extern int MidMAPeriod = 21;
extern int MidMAType = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int MidMAPrice = 0;
extern int MidMAShift = 0;
//---------------------
extern int SlowMATime = 0;
extern int SlowMAPeriod = 34;
extern int SlowMAType = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int SlowMAPrice = 0;
extern int SlowMAShift = 0;

//---- G#MACD input parameters
extern string separator2 = "*** G#MACD Settings ***";
extern int     FastEMA=8;
extern int    FFastEMA=7;
extern int   FFFastEMA=6;
extern int     SlowEMA=17;
extern int    SSlowEMA=16;
extern int   SSSlowEMA=15;
extern int   SignalSMA=9;
extern int  SSignalSMA=8;
extern int SSSignalSMA=7;
extern string separator3 = "*** Indicator Settings ***";
extern bool   drawIndicatorTrendLines = true;
extern bool   drawPriceTrendLines = true;
extern bool   displayAlert = false;
//---- buffers
double bullishDivergence[];
double bearishDivergence[];
double macd[];
double signal[];
//----
static datetime lastAlertTime;
static string   indicatorName;

// Global Variables

int Counter, vSlippage;
double ticket, number, vPoint;

// Structural #3 (Optional): expert initialization function

int init() {

	if(Digits==3 || Digits==5) {
		vPoint=Point*10; vSlippage=Slippage*10;
	}
	else {
		vPoint=Point; vSlippage=Slippage;
	}

	return(0);
}

// Structure #4 (Optional): expert deinitialization function

int deinit() {
//----  shutdown code
	return(0);
}

// Structure #5 (Essential): expert start function

int start() {

	if(Bars<100) {
		Print("Bars less than 100");
		return(0);
	}
	
//--------------------------------------------------------
// Section 3A: Define ShortCuts to Common Functions

	if( TrailingStop>0 && TrailingStart > 0 )
		TrailOrder (TrailingStart, TrailingStop); 

	bool CloseBuy=false, CloseSell=false, OpenBuy=false, OpenSell=false;
	bool BuyCondition = false, SellCondition = false;
	
//	int OType=-1, OTicket;
//	double OOPrice, OSL, OTP, OLot;
//	for(int Counter=1; Counter<=OrdersTotal(); Counter++)
//	{
//		if (OrderSelect(Counter-1,SELECT_BY_POS)==true)
//			if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)	{
//				OTicket=OrderTicket();
//				OType=OrderType();
//				OOPrice=OrderOpenPrice();
//				OSL=OrderStopLoss();
//				OTP=OrderTakeProfit();
//				OLot=OrderLots();
//				break;
//			}
//	}
//----------------------------------------------------
// Section 3B: Indicator Calling

//   if(MAFilter || MAFilterRev) {
////	double mafilter=iMA(NULL,MATime,MAPeriod,0,MAMethod,PRICE_CLOSE,MAShift);
//		double mafilterF=iMA(NULL,FastMATime,FastMAPeriod,0,FastMAType,PRICE_CLOSE,FastMAShift);
//		double mafilterM=iMA(NULL,MidMATime,MidMAPeriod,0,MidMAType,PRICE_CLOSE,MidMAShift);
//		double mafilterS=iMA(NULL,SlowMATime,SlowMAPeriod,0,SlowMAType,PRICE_CLOSE,SlowMAShift);
//	}
	
	double BuySignal = iCustom(NULL,0,"G#MACD_Divergence",separator1,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator2,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,0,2);
//	Print("BuySignal=",BuySignal);
	if( BuySignal < 100 ) {
		BuyCondition=true;
	}
	else {
		double SellSignal = iCustom(NULL,0,"G#MACD_Divergence",separator1,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator2,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,1,2);
//		Print("SellSignal=",SellSignal);
		if( SellSignal<100 )
			SellCondition=true;
	}
	
	if( !BuyCondition && !SellCondition )
		return(0);
//------------------------------------------------
// Section 3C: Entry Conditions

	bool OpenBar=true;
	if(EnterOpenBar)
		if(iVolume(NULL,0,0)>1)
			OpenBar=false;
	
	if(!OpenBar)
		return(0);

	double LotSize = 0, TradeSL, TradeTP, lastOrderPrice;
	int pips=0;
	bool pipsOk=true;

	if( BuyCondition )
	{
//			(MAFilter==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) &&
//			(MAFilterRev==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) ) {
//			(MAFilter==false || (MAFilter && Ask>mafilter)) &&
//			(MAFilterRev==false || (MAFilter && Ask<mafilter)) ) {
		TradeSL=GetStopLoss(OP_BUY);
		pips = GetPips(Bid,TradeSL);
		if( MaxPips > 0 && pips > MaxPips )
		{
			Print("MaxPips=",MaxPips,",",pips);
			pipsOk=false;
		} else
			if(	MinPips > 0 && pips < MinPips )
				pipsOk=false;
		if(	pipsOk )
		{
			if( !MatchLastOrderPrice(Bid) ) {
				OpenBuy = true;
				if(OppositeClose)
					CloseSell = true;
			}
		}
		else
		{
			OpenBuy = false;
			if( ForceOppositeClose )
				if(OppositeClose)
					CloseBuy=true;
		}
	} else
		if( SellCondition )
		{
//				(MAFilter==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) &&
//				(MAFilterRev==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) ) {
//				(MAFilter==false || (MAFilter && Bid<mafilter)) &&
//				(MAFilterRev==false || (MAFilter && Bid>mafilter)) ) {
			TradeSL=GetStopLoss(OP_SELL);
			pips = GetPips(Ask,TradeSL);
			if( MaxPips > 0 && pips > MaxPips )
			{
				Print("MaxPips=",MaxPips,",",pips);
				pipsOk=false;
			} else
				if(	MinPips > 0 && pips < MinPips )
					pipsOk=false;
			if(	pipsOk )
			{
				if( !MatchLastOrderPrice(Ask) ) {
					OpenSell = true;
					if(OppositeClose)
						CloseBuy=true;
				}
			}
			else
			{
				OpenSell = false;
				if( ForceOppositeClose )
					if(OppositeClose)
						CloseBuy=true;
			}
		}

	Print("EntryCond:",BuyCondition,",",SellCondition,",",
			OpenBuy,",",CloseSell,",",OpenSell,",",CloseBuy,",",pips);
//-------------------------------------------------
// Section 3D: Close Conditions

	if( CloseBuy==true )
		close(OP_BUY); // Close Buy
	if( CloseSell==true )
		close(OP_SELL); // Close Sell
		
	if( AdjustStop ) {
		if( BuyCondition && !OpenBuy )
			adjustStop(OP_SELL);
		if( SellCondition && !OpenSell )
			adjustStop(OP_BUY);
	}
//--------------------------------------------------
// Section 3E: Order Placement
	
	if(!OpenBuy && !OpenSell)
		return(0);
	
	while(true)
	{
		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenBuy==true)
		{
//			TradeSL=GetStopLoss(OP_BUY);
			LotSize = GetLots(pips);
			if(LotSize<=0)
				break;
			
			if(TakeProfit>0) {
				TradeTP=Bid+TakeProfit*vPoint;
			} else {
				TradeTP=0;
			}
			
			ticket=0;number=0;
			while(ticket<=0 && number<20)
			{
				number = number+1;
				RefreshRates();
				ticket = OrderSend(Symbol(),OP_BUY,LotSize, 
								Ask,vSlippage,TradeSL,TradeTP,EAName, MagicNumber, 0, Green);
				if(ticket<=0)
				{
					int error=GetLastError();
					Print("ERR:OrderSend:",number,",",error);
				}
//				return (ticket);
			}
		}

		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenSell==true)
		{
//			TradeSL=GetStopLoss(OP_SELL);
			LotSize = GetLots(pips);
			if(	LotSize<=0 )
				break;

			if(	TakeProfit>0) {
				TradeTP=Ask-TakeProfit*vPoint;
			} else {
				TradeTP=0;
			}
			ticket=0;number=0;
			while(ticket<=0 && number<20){
				number = number+1;
				RefreshRates();
				ticket= OrderSend(Symbol(),OP_SELL, LotSize,
								Bid,vSlippage,TradeSL,TradeTP, EAName, MagicNumber, 0, Red);
				if(	ticket<=0 ){
					error=GetLastError();
					Print("ERR:OrderSend:",number,",",error);
				}
//				return (ticket);
			}
		}
		
//		Print("TP=",TradeTP);
		break;
	}
//---------------------------------------------------------
	if(	ticket>0 )
		return(ticket);
// End of start()
	return(0);
}

// Structure #6 (Optional): Custom Functions

// Section 4A: Close Function

void close(int type)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if(oTotal<=0)
		return;
		
	Print("close:",type,",",oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		double oLots = OrderLots();
		int oType = OrderType();
		Print("close:",Counter,":",oTicket,",",OrderSymbol(),",",oType,",",OrderMagicNumber());
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber )
			continue;
		RefreshRates();	
		if(type==OP_BUY && oType==OP_BUY){
//			if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
//				RefreshRates();
				OrderClose(oTicket,oLots,NormalizeDouble(Bid,Digits), vSlippage);
				Comment("Close ",oTicket,":",oLots,"lots at bid=",Bid);
//			}
		}
		if(type==OP_SELL && oType==OP_SELL){
//			if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
//				RefreshRates();
				OrderClose(oTicket,oLots,NormalizeDouble(Ask,Digits),vSlippage);
				Comment("Close ",oTicket,":",oLots,"lots at ask=",Ask);
//			}
		}
	}
}

void adjustStop(int type)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if(oTotal<=0)
		return;
		
	Print("adjustStop1:",type,",",oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		double oLots = OrderLots();
		Print("adjustStop2:",Counter,":",oTicket,",",OrderSymbol(),",",OrderMagicNumber());
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber )
			continue;
		Print("adjustStop3:",oTicket,",",OrderProfit());
		if( OrderProfit()<=0 )
			continue;
		RefreshRates();	
		int ticket=0;
		ticket = OrderModify(oTicket,OrderOpenPrice(),OrderOpenPrice(),OrderTakeProfit(),0,Blue);
		Print ("adjustStopModify:", oTicket,",",ticket,",",OrderSymbol(),",", OrderOpenPrice(), OrderOpenPrice());
	}
}

// Section 4B: OrdersTotalMagicOpen Function

int OrdersTotalMagicOpen()
{
	int OrderCount = 0;
	for (int l_pos_4 = OrdersTotal() - 1; l_pos_4 >= 0; l_pos_4--)
	{
		OrderSelect(l_pos_4, SELECT_BY_POS, MODE_TRADES);
		if (OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
			continue;
		if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
			if (OrderType() == OP_SELL || OrderType() == OP_BUY)
				OrderCount++;
	}
	return (OrderCount);
}

int GetPips(double entryPrice, double stopLossPrice)
{
	double pips;
	if(entryPrice>stopLossPrice)
		pips=(entryPrice - stopLossPrice) * MathPow(10,Digits-1);
	else
		pips=(stopLossPrice - entryPrice) * MathPow(10,Digits-1);
	Print("GetPips=",pips,",",MinPips,",",MaxPips);
	return(NormalizeDouble(pips,0));
}

double GetLots(int pips)
{
	double minlot = MarketInfo(Symbol(), MODE_MINLOT);
	double maxlot = MarketInfo(Symbol(), MODE_MAXLOT);
	double leverage = AccountLeverage();
	double lotsize = MarketInfo(Symbol(), MODE_LOTSIZE);
	double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL);

	double MinLots = 0.01; double MaximalLots = 50.0;
	double lots = 0;

//	if(MM) {
		double usdsgdRate= NormalizeDouble(iClose("USDSGD",PERIOD_D1,1),LotDigits);
		double cashAtRisk = NormalizeDouble(AccountFreeMargin() * RiskRatio/100, LotDigits);
			
		if(	(MinPips > 0 && pips < MinPips) ||
			(MaxPips > 0 && pips > MaxPips) )
			return(-1);
			
		double RValue = pips * usdsgdRate;
		double stopCost = RValue * 10;

		lots = NormalizeDouble(cashAtRisk / stopCost, LotDigits);
		Print("MM:", NormalizeDouble(AccountFreeMargin(),LotDigits),":Pips=",pips,">",MinPips,
			":UsdSgd=",usdsgdRate,",CshRisk=",cashAtRisk,",Rval=",RValue,",Lots=",lots);
		Comment("MM:", NormalizeDouble(AccountFreeMargin(),LotDigits),":Pips=",pips,">",MinPips,
			":UsdSgd=",usdsgdRate,",CshRisk=",cashAtRisk,",Rval=",RValue,",Lots=",lots);

//		lots = NormalizeDouble(AccountFreeMargin() * RiskRatio/100 / 1000.0, LotDigits);
//		if(lots < minlot) lots = minlot;
		if(lots < minlot)
		{
			Print("Insufficient fund:", lots, " , minlot=", minlot);
			lots = -1;
			return (lots);
		}
		if(lots > MaximalLots) lots = MaximalLots;
		if(AccountFreeMargin() < Ask * lots * lotsize / leverage) {
			Print("We have no money. Lots = ", lots, " , Free Margin = ", AccountFreeMargin());
		}
//	}
//	else
//		lots=NormalizeDouble(Lots,Digits);
		
	return(lots);
}

void TrailOrder(double Trailingstart,double Trailingstop)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if(oTotal<=0)
		return;
		
	int ticket = 0, cnt=0;

	for(cnt=oTotal-1;cnt>=0;cnt--)
	{
		OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		int oType = OrderType();
		double ooPrice = OrderOpenPrice();
		double sl,tStopLoss = NormalizeDouble(OrderStopLoss(), Digits); // Stop Loss
		
		if(oType<=OP_SELL && OrderSymbol()==Symbol()
			&& OrderMagicNumber()==MagicNumber){

//			Print("TrailOrder:",oTotal,":",OType,":",Trailingstart,":",Trailingstop);
			
			if(oType==OP_BUY)
			{
				if(Ask> NormalizeDouble(ooPrice+TrailingStart* vPoint,Digits)
					&& tStopLoss < NormalizeDouble(Bid-(TrailingStop+TrailingStep)*vPoint,Digits)){
					tStopLoss = NormalizeDouble(Bid-TrailingStop*vPoint,Digits);
					ticket = OrderModify(oTicket,ooPrice,tStopLoss,OrderTakeProfit(),0,Blue);
					if (ticket > 0){
						Print ("TrailingStop #1 Activated: ", OrderSymbol(), ": SL", tStopLoss, ": Bid", Bid);
						continue;
					}
				}
			}

			if (oType==OP_SELL)
			{
				if (Bid < NormalizeDouble(ooPrice-TrailingStart*vPoint,Digits)
					&& (sl >(NormalizeDouble(Ask+(TrailingStop+TrailingStep)*vPoint,Digits)))
					|| (OrderStopLoss()==0))
				{
					tStopLoss = NormalizeDouble(Ask+TrailingStop*vPoint,Digits);
					ticket = OrderModify(oTicket,OrderOpenPrice(),tStopLoss,OrderTakeProfit(),0,Red);
					if (ticket > 0)
					{
						Print ("Trailing #2 Activated: ", OrderSymbol(), ": SL ",tStopLoss, ": Ask ", Ask);
//						return(0);
					}
				}
			}
		}
	}
}

double GetStopLoss(int dir)
{
	double stopLoss,stopLossTol;
	// stop = lowest Low of the last 3 bars
	if(dir == OP_BUY)
	{
		stopLoss = Low[iLowest(Symbol(), 0, MODE_LOW, StopLossBarCount, 1)];
		Print("GetStopLoss:",stopLoss);
//		stopLoss = stopLoss - (stopLoss * StopLossTolerancePc/100);
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss - stopLossTol;
	}

	else if(dir == OP_SELL)
	{
		stopLoss = High[iHighest(Symbol(), 0, MODE_HIGH, StopLossBarCount, 1)];
		Print("GetStopLoss:",stopLoss);
//		stopLoss = stopLoss + (stopLoss * StopLossTolerancePc/100); 
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss + stopLossTol;
	}
	
	Print("GetStopLoss:",dir==OP_BUY,":",stopLossTol,":",stopLoss);
	return(stopLoss);
}

bool MatchLastOrderPrice(double entryPrice) {
	if(!MatchLastOrder)
		return(false);
	int oTotal = OrdersTotal();
//	Print("MatchLastOrderPrice:",oTotal);
	if( oTotal<=0 )
		return(false);
		
	OrderSelect(oTotal-1,SELECT_BY_POS,MODE_TRADES);
	double pips=(MathAbs(entryPrice - OrderOpenPrice())) * MathPow(10,Digits-1);
	bool retval;
	if( pips<=(MaxPips/2) )
		retval = true;
	Print("MatchLastOrderPrice:",retval,":",OrderTicket(),",",OrderOpenPrice(),",",pips);
	return(retval);
}