//+--------------------------------------------------------+
//| G#MACD_Divergence_EA.mq4
//| Copyright © 2013, roysten
//|
//| Version History:
//|		v1.x	Single trade
//|		v2.0	Multiple trades
//|		v2.1	Skip trade if price still matches last order (with orderModify error)
//|		v2.2	Adjust stops to protect profits if opposite trade signal is not taken
//|		v2.3	Replace close by adjusting SL, add partial close
//|		v2.4	Add support and resistance
//|		v2.5	Parameterize options from booleans to facilitate backtesting
//|
//|	OrderType 		Integer 	Description
//|	---------------------------------------
//|	OP_BUY 				0 		Buy Position
//|	OP_SELL 			1 		Sell Position
//|	OP_BUYLIMIT 		3 		Buy Limit Pending
//|	OP_BUYSTOP 			4 		Buy Stop Pending
//|	OP_SELLLIMIT 		5 		Sell Limit Pending
//|	OP_SELLSTOP 		6 		Sell Stop Pending
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
extern int stopType = 0;			// 0=stopBarCount, 1=SR level
extern int NoClose = 0;				// 0=false, 1=true
extern int ForceOppositeClose = 0;	// 0=false, 1=true
extern int OppositeClose = 0;		// 0=false, 1=true
extern int AdjustStop = true;		// 0=false, 1=true
extern int ConcurrentOrders = 0;	// 0=no limit
extern double RiskRatio = 2;
extern int MinPips = 10;
extern int MaxPips = 200;
extern double LotDigits =2;
extern int TakeProfit = 0;
extern int PartialClosePortion = 0;
extern int StopLossBarCount = 1;
extern int StopLossTolerancePc = 0;
extern int PipsTolerance = 0;		// 0=no extra pips
extern int SR_Tolerance = 0;

extern double TrailingStart = 500;
extern double TrailingStop  = 250;
extern double TrailingStep  = 50;

extern int  Slippage = 5;
extern bool EnterOpenBar = true;
extern bool MatchLastOrder = true;
extern bool GapCheck=true;
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
//---- S&R buffers
double v1[];
double v2[];
double val1;
double val2;
int i;
//----
static datetime lastAlertTime;
static string   indicatorName;

// Global Variables

int Counter, vSlippage;
double ticket, number, vPoint, RValue;

// Structural #3 (Optional): expert initialization function

int init() {
	if(Digits==3 || Digits==5) {
		vPoint=Point*10; vSlippage=Slippage*10;
	}
	else {
		vPoint=Point; vSlippage=Slippage;
	}
	Print("init:vP=",vPoint);
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
	
	//	Safety Measure: Close if gap crossed SL
	if( GapCheck ) {
//		double stopGapBal = NormalizeDouble(AccountBalance() * (RiskRatio+1)/100, LotDigits);
		for(int Counter=1; Counter<=OrdersTotal(); Counter++) {
			if( OrderSelect(Counter-1,SELECT_BY_POS)==true &&
				OrderMagicNumber() == MagicNumber ) {
				if( OrderType()==OP_BUY && OrderProfit()<0 &&
					Bid < OrderStopLoss() ) {
//					MathAbs(OrderProfit())>stopGapBal ) {
					OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Bid,Digits), vSlippage, Red);
					Print("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit());
					Alert("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit());
//					Print("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
//					Alert("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
				}
				if( OrderType()==OP_SELL && OrderProfit()<0 &&
					Ask > OrderStopLoss() ) {
//					MathAbs(OrderProfit())>stopGapBal ) {
					OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Ask,Digits), vSlippage, Red);
					Print("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit());
					Alert("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit());
//					Print("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
//					Alert("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
				}
			}
		}
	}
//----------------------------------------------------
// Section 3B: Indicator Calling

//   if(MAFilter || MAFilterRev) {
////	double mafilter=iMA(NULL,MATime,MAPeriod,0,MAMethod,PRICE_CLOSE,MAShift);
//		double mafilterF=iMA(NULL,FastMATime,FastMAPeriod,0,FastMAType,PRICE_CLOSE,FastMAShift);
//		double mafilterM=iMA(NULL,MidMATime,MidMAPeriod,0,MidMAType,PRICE_CLOSE,MidMAShift);
//		double mafilterS=iMA(NULL,SlowMATime,SlowMAPeriod,0,SlowMAType,PRICE_CLOSE,SlowMAShift);
//	}
	
	double BuySignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,0,2);
//	Print("BuySignal=",BuySignal);
	if( BuySignal < 100 ) {
		BuyCondition=true;
	}
	else {
		double SellSignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,1,2);
//		Print("SellSignal=",SellSignal);
		if( SellSignal<100 )
			SellCondition=true;
	}
	
	if( !BuyCondition && !SellCondition )
		return(0);
		
	double R = iCustom(NULL,0,"Support and Resistance (Barry)",0,0);
	double S = iCustom(NULL,0,"Support and Resistance (Barry)",1,0);
//	Print("Barry:R=",R,",S=",S);
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
		if( stopType==0 )
			TradeSL = GetStopLoss(OP_BUY);
		else
		if( stopType==1 )
			TradeSL = S - (SR_Tolerance * vPoint);
		if( TradeSL>0 )
		{
			pips = GetPips(Ask,TradeSL);
			TradeSL = Ask - (pips*vPoint);
			if( MaxPips > 0 && pips > MaxPips )
			{
				Print("MaxPips=",MaxPips,">",pips);
				pipsOk=false;
			} else
				if(	MinPips > 0 && pips < MinPips )
					pipsOk=false;
			if(	pipsOk )
			{
				if( !MatchLastOrderPrice(Ask) ) {
					OpenBuy = true;
					if( OppositeClose>0 )
						CloseSell = true;
				}
			}
			else
			{
				OpenBuy = false;
				if( ForceOppositeClose>0 )
					if( OppositeClose>0 )
						CloseBuy=true;
			}
		}
	} else
		if( SellCondition )
		{
//				(MAFilter==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) &&
//				(MAFilterRev==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) ) {
//				(MAFilter==false || (MAFilter && Bid<mafilter)) &&
//				(MAFilterRev==false || (MAFilter && Bid>mafilter)) ) {
			if( stopType==0 )
				TradeSL = GetStopLoss(OP_SELL);
			else
			if( stopType==1 )
				TradeSL = R + (SR_Tolerance * vPoint);
			if( TradeSL>0 )
			{
				pips = GetPips(Bid,TradeSL);
				TradeSL = Bid + (pips*vPoint);
				if( MaxPips > 0 && pips > MaxPips )
				{
					Print("MaxPips=",MaxPips,"<",pips);
					pipsOk=false;
				} else
					if(	MinPips > 0 && pips < MinPips )
						pipsOk=false;
				if(	pipsOk )
				{
					if( !MatchLastOrderPrice(Bid) ) {
						OpenSell = true;
						if( OppositeClose>0 )
							CloseBuy=true;
					}
				}
				else
				{
					OpenSell = false;
					if( ForceOppositeClose>0 )
						if( OppositeClose>0 )
							CloseBuy=true;
				}
			}
		}

	Print("R=",R,",S=",S,",SL=",TradeSL,",P=",pips);
	Print("EntryCond:bc=",BuyCondition,",sc=",SellCondition,
		",ob=",OpenBuy,",cs=",CloseSell,",os=",OpenSell,",cb=",CloseBuy);
//-------------------------------------------------
// Section 3D: Close Conditions

	if( CloseBuy==true )
		if( NoClose==1 )
			adjustStop(OP_BUY,R,S);
		else
			close(OP_BUY); // Close Buy
	if( CloseSell==true )
		if( NoClose==1 )
			adjustStop(OP_SELL,R,S);
		else
			close(OP_SELL); // Close Sell
		
	if( AdjustStop>0 ) {
		if( BuyCondition && !OpenBuy )
			adjustStop(OP_SELL,R,S);
		if( SellCondition && !OpenSell )
			adjustStop(OP_BUY,R,S);
	}
//--------------------------------------------------
// Section 3E: Order Placement
//	Buy at Ask, Sell at Bid
	
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
//				TradeTP=Bid+TakeProfit*vPoint;
				TradeTP=Bid+(TakeProfit*RValue*vPoint);
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
					Print("ERR:OrderSend:",number,",",error,",Pt=",vPoint,
						",Ask=",Ask,",sl=",TradeSL,",tp=",TradeTP);
					if( error==130 ||
						error==4107 )	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
						break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
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
//				TradeTP=Ask-TakeProfit*vPoint;
				TradeTP=Ask-(TakeProfit*RValue*vPoint);
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
					Print("ERR:OrderSend:",number,",",error,",Pt=",vPoint,
						",Bid=",Bid,",sl=",TradeSL,",tp=",TradeTP);
					if( error==130 )	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS), 138 (ERR_REQUOTE)
						break;
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

void adjustStop(int dir, double R, double S)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if( oTotal<=0 )
		return;
		
	Print("adjustStop1:",dir,"(0=B,1=S),",oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		int ticket=0,oType=OrderType();
		if( oType!=dir ) {
			Print("adjustStop2:Abort oTic=",oTicket);
			continue;
		}
		if( OrderProfit()<=0 ) {
			Print("adjustStop3:Abort oTic=",oTicket);
			continue;
		}
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber ) {
			Print("adjustStop4:Abort oTic=",oTicket);
			continue;
		}
		double SL,ooPrice = OrderOpenPrice(), oSL=OrderStopLoss();
//		if( (oType==OP_BUY && oSL < ooPrice) ||
//			(oType==OP_SELL && oSL > ooPrice) )
//			SL = ooPrice;	// Protect profits already gained
//		else
//			SL = GetStopLoss(oType);

		Print("adjustStop5:",Counter,":oTic=",oTicket,",oType=",oType,",oProfit=",OrderProfit(),",",OrderMagicNumber());
/*
		int stopDistance;
		if( oType==OP_BUY ) {
			stopDistance = (S - oSL) / vPoint;
			Print("adjustStop6:oTic=",oTicket,",oSL=",oSL,",S=",S,",SD=",stopDistance,",nSL=",S-SR_Tolerance*vPoint);
			if( S<oSL ||						// do not adjust if support below SL, or
				stopDistance < SR_Tolerance )	// SL already close to support level
				continue;
			SL = S - (SR_Tolerance*vPoint);
			if( SL<oSL )
				continue;
		} else
		if( oType==OP_SELL ) {
			stopDistance = (oSL - R) / vPoint;
			Print("adjustStop7:oTic=",oTicket,",oSL=",oSL,",R=",R,",SD=",stopDistance,",nSL=",R+SR_Tolerance*vPoint);
			if( R>oSL ||						// do not adjust if resistance above SL, or
				stopDistance < SR_Tolerance )	// SL already close to resistance level
				continue;
			SL = R + (SR_Tolerance*vPoint);
			if( SL>oSL )
				continue;
		}
*/
/*
		if( oType==OP_BUY ) {
			if( S<oSL )
				continue;
			SL = S;
			if( SL<oSL )
				continue;
		} else
		if( oType==OP_SELL ) {
			if( R>oSL )
				continue;
			SL = R;
			if( SL>oSL )
				continue;
		}
*/
		SL = GetStopLoss(oType);
		
		if( oType==OP_BUY ) {
			if( SL<oSL )
				continue;
		} else
		if( oType==OP_SELL ) {
			if( SL>oSL )
				continue;
		}
		
		Print("adjustStop8:oTic=",oTicket,",ooP=",ooPrice,",R=",R,",S=",S,",oSL=",oSL,",nSL=",SL);
		
		if( SL!=ooPrice ) {
			if(	oType==OP_BUY )
				ooPrice = Ask;
			else
				ooPrice = Bid;
			if( GetPips(ooPrice,SL) < 0 ) {
				Print("adjustStop9:Abort oTic=",oTicket);
				continue;
			}
		}
		RefreshRates();
		ticket = OrderModify(oTicket,ooPrice,SL,OrderTakeProfit(),0,Blue);
		Print("adjustStopModify:Dir=",dir,",oTic=",oTicket,",nTic=",ticket,
				",OOP=",ooPrice,",SL=", SL,",Ask=",Ask,",Bid=",Bid,",bal=",AccountBalance());
				
		if( SL!=ooPrice && TakeProfit>0 && PartialClosePortion>0 ) {
			double cLots = NormalizeDouble(OrderLots()/PartialClosePortion,2);
			if( cLots>0 ) {
				double halfProfit;
				if( oType==OP_BUY ) {
					halfProfit = oSL + (OrderTakeProfit() - oSL) / 2;
					if( Bid >= halfProfit ) {
						OrderClose(oTicket,cLots,Bid,vSlippage,Red);
//						Print("LE=",GetLastError());
					}
				} else
				if( oType==OP_SELL ) {
					halfProfit = oSL - (oSL - OrderTakeProfit()) / 2;
					if( Ask <= halfProfit ) {
						OrderClose(oTicket,cLots,Ask,vSlippage,Red);
//						Print("LE=",GetLastError());
					}
				}
				Print("PartialClose:oTic=",oTicket,",cL=",cLots,",hp=",halfProfit,",a=",Ask,",b=",Bid,
						",sl=",oSL,",tp=",OrderTakeProfit(),",bal=",AccountBalance());
			}
		}
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

int GetPips(double entryPrice, double exitPrice)
{
	double slPips;
	if( entryPrice>exitPrice )
		slPips=(entryPrice - exitPrice) / vPoint;
	else
		slPips=(exitPrice - entryPrice) / vPoint;
	
	if( PipsTolerance>0 ) {
		int tolPips = NormalizeDouble((slPips * PipsTolerance/100),0);
		slPips = slPips + tolPips;
	} else
		if( SR_Tolerance>0 )
			slPips = slPips + SR_Tolerance;
	
//	int mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
//	Print("GetPips:eP=",entryPrice,",eP=",exitPrice,":mktP=",mktPips,",P=",slPips,
//			",tolP=",tolPips,",srT=",SR_Tolerance,",slP=",slPips - SR_Tolerance);
//	if(slPips < mktPips)
//		return(-1);
	Print("GetPips:eP=",entryPrice,",eP=",exitPrice,":minP=",MinPips,",P=",slPips,
			",tolP=",tolPips,",srT=",SR_Tolerance,",slP=",slPips - SR_Tolerance);
	if(slPips < MinPips)
		return(-1);
	return(slPips);
//	return(NormalizeDouble(slPips,0));
}

double GetLots(int pips)
{
	double leverage  = AccountLeverage();
	double minlot    = MarketInfo(Symbol(), MODE_MINLOT);
	double maxlot    = MarketInfo(Symbol(), MODE_MAXLOT);
	double lotsize   = MarketInfo(Symbol(), MODE_LOTSIZE);
//	double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL);

	double MinLots = 0.01; double MaximalLots = 50.0;
	double lots = 0;

//	if(MM) {
		if(	(MinPips > 0 && pips < MinPips) ||
			(MaxPips > 0 && pips > MaxPips) )
			return(-1);
			
		double usdsgdRate = NormalizeDouble(iClose("USDSGD",PERIOD_D1,1),LotDigits);
		double cashAtRisk = NormalizeDouble(AccountFreeMargin() * RiskRatio/100, LotDigits);
		
		RValue = pips * usdsgdRate;
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
			lots = -1;
			return (lots);
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
	if( oTotal<=0 )
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

bool MatchLastOrderPrice(double entryPrice) {
	if(!MatchLastOrder)
		return(false);
	int oTotal = OrdersTotal();
//	Print("MatchLastOrderPrice:",oTotal);
	if( oTotal<=0 )
		return(false);
		
	OrderSelect(oTotal-1,SELECT_BY_POS,MODE_TRADES);
//	double pips=(MathAbs(entryPrice - OrderOpenPrice())) * MathPow(10,Digits-1);
	double prevPips=MathAbs(OrderStopLoss() - OrderOpenPrice()) / vPoint;
	double currPips=MathAbs(entryPrice - OrderOpenPrice()) / vPoint;
	bool retval=false;
//	if( mPips<=(MaxPips/2) )
	if( currPips < (prevPips/2) )
		retval = true;	// too close to last order entry price
	Print("MatchLastOrderPrice:oTic=",OrderTicket(),",ooP=",OrderOpenPrice(),",pP=",prevPips,",cP=",currPips);
	return(retval);
}