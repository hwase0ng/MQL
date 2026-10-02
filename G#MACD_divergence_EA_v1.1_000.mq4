//+--------------------------------------------------------+
//| G#MACD_Divergence_EA.mq4
//| Copyright © 2013, roysten
//+--------------------------------------------------------+
// Structure #1 (Optional): Directives
#property copyright "Copyright © 2013, roysten.tan@gmail.com"
#include <stderror.mqh>
#include <stdlib.mqh>

// Structure #2 (Optional): Input parameters

extern string EAName = "G#MACD_Divergence_EA";
extern double MagicNumber = 8033;
extern int TimeFrame = 240;

//extern bool MM = TRUE;
extern int ConcurrentOrders = 3;
extern double Risk = 2;
extern double PipsMargin = 20;
extern double LotDigits =2;
extern int TakeProfit = 0;
extern int StopLossBarCount = 1;
extern int StopLossTolerancePc = 0;

extern double TrailingStart = 50;
extern double TrailingStop = 25;
extern double TrailingStep = 5; 

extern int Slippage = 5;
extern bool OppositeClose = true;
extern bool EnterOpenBar = true;

//---- MA Filter input parameters
extern string separator1 = "*** MA Filter Settings ***";
extern bool MAFilter=false;
extern bool MAFilterRev = false;
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
extern int       FastEMA=8;
extern int       FFastEMA=7;
extern int       FFFastEMA=6;
extern int       SlowEMA=17;
extern int       SSlowEMA=16;
extern int       SSSlowEMA=15;
extern int       SignalSMA=9;
extern int       SSignalSMA=8;
extern int       SSSignalSMA=7;
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

	if(TrailingStop>0 && TrailingStart > 0)
		TrailOrder (TrailingStart, TrailingStop); 

	int Total, OType=-1, Ticket;
	double Price, SL, TP, Lot;
	bool CloseBuy=false, CloseSell=false, OpenBuy=false, OpenSell=false;
	bool BuyCondition = false, SellCondition = false;
	
	for(int Counter=1; Counter<=OrdersTotal(); Counter++)
	{
		if (OrderSelect(Counter-1,SELECT_BY_POS)==true)
			if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)	{
				Ticket=OrderTicket();
				OType =OrderType();
				Price =OrderOpenPrice();
				SL =OrderStopLoss();
				TP =OrderTakeProfit();
				Lot =OrderLots();
			}
	}
//----------------------------------------------------
// Section 3B: Indicator Calling

   if(MAFilter || MAFilterRev) {
//		double mafilter=iMA(NULL,MATime,MAPeriod,0,MAMethod,PRICE_CLOSE,MAShift);
		double mafilterF=iMA(NULL,FastMATime,FastMAPeriod,0,FastMAType,PRICE_CLOSE,FastMAShift);
		double mafilterM=iMA(NULL,MidMATime,MidMAPeriod,0,MidMAType,PRICE_CLOSE,MidMAShift);
		double mafilterS=iMA(NULL,SlowMATime,SlowMAPeriod,0,SlowMAType,PRICE_CLOSE,SlowMAShift);
	}
	
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
//------------------------------------------------
// Section 3C: Entry Conditions

	bool OpenBar=true;
	if(EnterOpenBar)
		if(iVolume(NULL,0,0)>1)
			OpenBar=false;

	if(OpenBar)  {
		if( BuyCondition && 
			(MAFilter==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) &&
			(MAFilterRev==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) ) {
//			(MAFilter==false || (MAFilter && Ask>mafilter)) &&
//			(MAFilterRev==false || (MAFilter && Ask<mafilter)) ) {
			OpenBuy=true;
			if(OppositeClose)
				CloseSell = true;
		} else
			if( SellCondition &&
				(MAFilter==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) &&
				(MAFilterRev==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) ) {
//				(MAFilter==false || (MAFilter && Bid<mafilter)) &&
//				(MAFilterRev==false || (MAFilter && Bid>mafilter)) ) {
				OpenSell = true;
				if(OppositeClose)
					CloseBuy=true;
			}
	}
	
	if(!OpenBuy && !OpenSell)
		return(0);
	Print("EntryCond:",OpenBuy,",",CloseSell,",",OpenSell,",",CloseBuy,",",OType);
//-------------------------------------------------
// Section 3D: Close Conditions

	while(true)
	{
		if (OType==0 && CloseBuy==true) {
			close (OP_BUY); // Close Buy
//			return;
		}
		if (OType==1 && CloseSell==true) {
			close (OP_SELL); // Close Sell
//			return;
		}
		break;
	}
//--------------------------------------------------
// Section 3E: Order Placement
	double LotSize = 0;
	
	while(true)
	{
		if (OrdersTotalMagicOpen()<=ConcurrentOrders && OpenBuy==true) {
			SL=GetStopLoss(OP_BUY);
			
			LotSize = GetLots(Bid,SL);
			if(LotSize<=0)
				break;
			
			if(TakeProfit>0) {
				TP=Bid+TakeProfit*vPoint;
			} else {
				TP=0;
			}
			
			ticket=0;number=0;
			while(ticket<=0 && number<20){
				number = number+1;
				RefreshRates();
				ticket = OrderSend(Symbol(),OP_BUY,LotSize, 
								Ask,vSlippage,SL,TP,EAName, MagicNumber, 0, Green);
//				return (ticket);
			}
		}

		if (OrdersTotalMagicOpen()<=ConcurrentOrders && OpenSell==true) {
			SL=GetStopLoss(OP_SELL);
			
			LotSize = GetLots(Ask,SL);
			if(LotSize<=0)
				break;

			if(TakeProfit>0) {
				TP=Ask-TakeProfit*vPoint;
			} else {
				TP=0;
			}
			ticket=0;number=0;
			while(ticket<=0 && number<20){
				number = number+1;
				RefreshRates();
				ticket= OrderSend(Symbol(),OP_SELL, LotSize,
								Bid,vSlippage,SL,TP, EAName, MagicNumber, 0, Red);
//				return (ticket);
			}
		}
		
//		Print("TP=",TP);
		break;
	}
//---------------------------------------------------------
	if(ticket>0)
		return(ticket);
// End of start()
	return(0);
}

// Structure #6 (Optional): Custom Functions

// Section 4A: Close Function

void close(int type){
	Print("close=",type,",",OrdersTotal());
	if(OrdersTotal()>0){
		for(Counter=OrdersTotal()-1;Counter>=0;Counter--){
			OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
			Print("OrderSelect:",Counter,":",OrderType(),",",OrderSymbol());
			if(type==OP_BUY && OrderType()==OP_BUY){
				if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
					RefreshRates();
					OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Bid,Digits), vSlippage);
				}
			}

			if(type==OP_SELL && OrderType()==OP_SELL){
				if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
					RefreshRates();
					OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Ask,Digits),vSlippage);
				}
			}
		}
	}
}


// Section 4B: OrdersTotalMagicOpen Function

int OrdersTotalMagicOpen() {
	int OrderCount = 0;
	for (int l_pos_4 = OrdersTotal() - 1; l_pos_4 >= 0; l_pos_4--) {
		OrderSelect(l_pos_4, SELECT_BY_POS, MODE_TRADES);
		if (OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
			continue;
		if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
			if (OrderType() == OP_SELL || OrderType() == OP_BUY)
				OrderCount++;
	}
	return (OrderCount);
}

double GetLots(double entryPrice, double stopLossPrice)
{
	Print("GetLots:", entryPrice,":",stopLossPrice);
	Comment("GetLots:", entryPrice,":",stopLossPrice);
	
	double minlot = MarketInfo(Symbol(), MODE_MINLOT);
	double maxlot = MarketInfo(Symbol(), MODE_MAXLOT);
	double leverage = AccountLeverage();
	double lotsize = MarketInfo(Symbol(), MODE_LOTSIZE);
	double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL);

	double MinLots = 0.01; double MaximalLots = 50.0;
	double lots = 0;

//	if(MM) {
		double usdsgdRate= iClose("USDSGD",PERIOD_D1,1);
		double cashAtRisk = NormalizeDouble(AccountFreeMargin() * Risk/100, LotDigits);
		double pips;
		if(entryPrice>stopLossPrice)
			pips=(entryPrice - stopLossPrice) * MathPow(10,Digits-1);
		else
			pips=(stopLossPrice - entryPrice) * MathPow(10,Digits-1);
			
		Print("PIPS=",pips,"<Margin=",PipsMargin,"?");
		if(pips < PipsMargin)
			return(-1);
			
		double RValue = pips * usdsgdRate;
		double stopCost = RValue * 10;

		lots = NormalizeDouble(cashAtRisk / stopCost, LotDigits);
		Print("MM:",AccountFreeMargin(),":",usdsgdRate,":",cashAtRisk,":",RValue,":",stopCost,":",lots);
		Comment("MM:", AccountFreeMargin(),":",usdsgdRate,":",cashAtRisk,":",RValue,":",stopCost,":",lots);

//		lots = NormalizeDouble(AccountFreeMargin() * Risk/100 / 1000.0, LotDigits);
//		if(lots < minlot) lots = minlot;
		if(lots < minlot) {
			Print("Insufficient fund:", lots, " , minlot=", minlot);
			Comment("Insufficient fund:", lots, " , minlot=", minlot);
			lots = -1;
			return (lots);
		}
		if(lots > MaximalLots) lots = MaximalLots;
		if(AccountFreeMargin() < Ask * lots * lotsize / leverage) {
			Print("We have no money. Lots = ", lots, " , Free Margin = ", AccountFreeMargin());
			Comment("We have no money. Lots = ", lots, " , Free Margin = ", AccountFreeMargin());
		}
//	}
//	else
//		lots=NormalizeDouble(Lots,Digits);
		
	return(lots);
}

void TrailOrder(double Trailingstart,double Trailingstop){
	RefreshRates();
	if(OrdersTotal()<=0)
		return;
		
	int ticket = 0, cnt=0;
	double sl,tStopLoss = NormalizeDouble(OrderStopLoss(), Digits); // Stop Loss

	for(cnt=OrdersTotal();cnt>=0;cnt--){
		OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES);
		if(OrderType()<=OP_SELL && OrderSymbol()==Symbol()
			&& OrderMagicNumber()==MagicNumber){

//			Print("TrailOrder:",OrdersTotal(),":",OrderType(),":",Trailingstart,":",Trailingstop);
			
			if(OrderType()==OP_BUY){
				if(Ask> NormalizeDouble(OrderOpenPrice()+TrailingStart* vPoint,Digits)
					&& tStopLoss < NormalizeDouble(Bid-(TrailingStop+TrailingStep)*vPoint,Digits)){
					tStopLoss = NormalizeDouble(Bid-TrailingStop*vPoint,Digits);
					ticket = OrderModify(OrderTicket(),OrderOpenPrice(),tStopLoss,OrderTakeProfit(),0,Blue);
					if (ticket > 0){
						Print ("TrailingStop #2 Activated: ", OrderSymbol(), ": SL", tStopLoss, ": Bid", Bid);
						return(0);
					}
				}
			}

			if (OrderType()==OP_SELL) {
				if (Bid < NormalizeDouble(OrderOpenPrice()-TrailingStart*vPoint,Digits)
					&& (sl >(NormalizeDouble(Ask+(TrailingStop+TrailingStep)*vPoint,Digits)))
					|| (OrderStopLoss()==0)){
					tStopLoss = NormalizeDouble(Ask+TrailingStop*vPoint,Digits);
					ticket = OrderModify(OrderTicket(),OrderOpenPrice(),tStopLoss,OrderTakeProfit(),0,Red);
					if (ticket > 0){
						Print ("Trailing #2 Activated: ", OrderSymbol(), ": SL ",tStopLoss, ": Ask ", Ask);
						return(0);
					}
				}
			}
		}
	}
}

double GetStopLoss(int dir) {
	double stopLoss,stopLossTol;
	// stop = lowest Low of the last 3 bars
	if(dir == OP_BUY)	{
		stopLoss = Low[iLowest(Symbol(), 0, MODE_LOW, StopLossBarCount, 1)];
		Print("GetStopLoss:",stopLoss);
//		stopLoss = stopLoss - (stopLoss * StopLossTolerancePc/100);
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss - stopLossTol;
	}

	else if(dir == OP_SELL)	{
		stopLoss = High[iHighest(Symbol(), 0, MODE_HIGH, StopLossBarCount, 1)];
		Print("GetStopLoss:",stopLoss);
//		stopLoss = stopLoss + (stopLoss * StopLossTolerancePc/100); 
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss + stopLossTol;
	}
	
	Print("GetStopLoss:",dir==OP_BUY,":",stopLossTol,":",stopLoss);
	Comment("GetStopLoss:",dir==OP_BUY,":",stopLossTol,":",stopLoss);
	return(stopLoss);
}