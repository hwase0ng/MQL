//+--------------------------------------------------------+
//| G#MACD_Divergence_EA.mq4
//| Copyright Â© 2013, roysten
//|
//| Version History:
//|		v1.x	Single trade
//|		v2.0	Multiple trades
//|		v2.1	Skip trade if price still matches last order (with orderModify error)
//|		v2.2	Adjust stops to protect profits if opposite trade signal is not taken
//|		v2.3	Replace close by adjusting SL, add partial close
//|		v2.4	Add support and resistance
//|		v2.5	Parameterize options from booleans to int for backtesting configuration
//|		v2.6	Establish market condition based on MAs
//|				Convert Print() to Log()
//|             New Pips.Match
//|		v2.7	New MarketCondition to determine trade action
//|		v2.8	Spotting MA convergence
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

#define VER "1.0"

// Structure #2 (Optional): Input parameters
extern double MagicNumber = 5045;
extern int TimeFrame = 240;

//extern bool MM = TRUE;
extern double RiskRatio = 5;
extern int ConcurrentOrders = 0;	// 0=no limit
extern int Count.HighR = 5;
extern int Count.LowS  = 5;

extern int Pips.Min = 10;
extern int Pips.Max = 150;
extern int Pips.Match = 0;			// 0 = no check
extern int Pips.BuyTrend.Margin = 20;
extern int Pips.SellTrend.Margin = 20;
extern int Pips.BUY_Tol = 10;		// 0=no extra pips
extern int Pips.SELL_Tol = 10;
extern int Pips.CompressedMA = 5;

extern double LotDigits =2;
extern int PartialClosePortion = 0;

extern double TrailingStart = 0;
extern double TrailingStop  = 0;
extern double TrailingStep  = 0;

extern int  Slippage = 5;
extern bool LogToFile = false;
extern bool EnterOpenBar = true;
extern bool Show.Comments = true;
extern bool GapCheck = true;
extern bool RevisePips = true;
//---- MA Filter input parameters
extern string separator1 = "*** MA Filter Settings ***";
extern int MAFilter = 1;		// 0=false, 1=true
extern int Pips.BuyAdjust.Start  = 150;
extern int Pips.SellAdjust.Start = 150;
extern int Pips.BuyStop_Entry = 15;
extern int Pips.SellStop_Entry = 15;
extern int Pips.BuyLimit_SL = 70;
extern int Pips.SellLimit_SL = 70;
//extern bool MAFilterRev = false;
//extern int MATime = 0;
//extern int MAPeriod = 50;
//extern int MAMethod=1;
//extern int MAShift=1;

extern int FFastMATime   = 0;
extern int FFastMAPeriod = 8;
extern int FFastMAType   = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FFastMAPrice  = 0;
extern int FFastMAShift  = 0;
//---------------------
extern int FastMATime    = 0;
extern int FastMAPeriod  = 21;
extern int FastMAType    = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FastMAPrice   = 0;
extern int FastMAShift   = 0;
//---------------------
extern int MidMATime     = 0;
extern int MidMAPeriod   = 34;
extern int MidMAType     = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int MidMAPrice    = 0;
extern int MidMAShift    = 0;
//---------------------
extern int SlowMATime    = 0;
extern int SlowMAPeriod  = 89;
extern int SlowMAType    = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int SlowMAPrice   = 0;
extern int SlowMAShift   = 0;
//---------------------
extern int SSlowMATime    = 0;
extern int SSlowMAPeriod  = 200;
extern int SSlowMAType    = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int SSlowMAPrice   = 0;
extern int SSlowMAShift   = 0;

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
double signal[];//---- S&R buffers
double v1[];
double v2[];
double val1;
double val2;
int i;
//----
static string EAName = "ma5045";

// Global Variables
#define UPTREND 1
#define UPTREND_REVERSAL 2
#define UPTREND_RETRACEMENT 3
#define UPRANGE 4
#define RANGE   5
#define DNRANGE 6
#define DNTREND 7
#define	DNTREND_REVERSAL 8
#define DNTREND_RETRACEMENT 9

int BuyMode[3], SellMode[3], MaxRetry=10, SleepCount=10000;
double bEntry[3], bExit[3], sEntry[3], sExit[3];
int Counter, vSlippage, error;
double ticket, number, vPoint, RValue;
double maFF,maF,maM,maS,maSS;
double lastMaFF,lastMaF,lastMaM,lastMaS,lastMaSS;
double normFF,normF,normM,normS,normSS;
double pMinF,pMidF,pMaxF,pMinM,pMidM,pMaxM,pMinS,pMidS,pMaxS;
int pips.madiff.FFF, pips.madiff.FM, pips.madiff.FFM;
int pips.madiff.MS, pips.madiff.FS;
int pips.madiff.SSS, pips.madiff.MSS;
int pips.MinMax.F,pips.MinMax.M,pips.MinMax.S;
int lastDistF,lastDistM,lastDistS;
int StopLossBarCount = 1;
bool DebugMode=false;

static double arrMA[5][5], arrDist[5];
static double arrMaF[5][3], arrDistF[5], arrMaM[5][3], arrDistM[5], arrMaS[5][3], arrDistS[5];

// Structural #3 (Optional): expert initialization function

int init() {
	if(Digits==3 || Digits==5) {
		vPoint=Point*10; vSlippage=Slippage*10;
	}
	else {
		vPoint=Point; vSlippage=Slippage;
	}
	Log("init:vP="+vPoint+":"+OP_BUY+","+OP_SELL+","+OP_BUYLIMIT+","+OP_SELLLIMIT+","+OP_BUYSTOP+","+OP_SELLSTOP);
	if( IsTesting() ){
		MaxRetry 	= 1;
		SleepCount	= 1;
		DebugMode	= true;
		if( !IsVisualMode()){
			Show.Comments   = false;
//			Show.Objects    = false;
			GapCheck        = false;
			DebugMode		= false;
		}
	}
	initMA();
	if(LogToFile){startFile();}
	LogSeparatorStart();
	return(0);
}

// Structure #4 (Optional): expert deinitialization function

int deinit() {
//----  shutdown code
	LogSeparatorEnd();
	return(0);
}

// Structure #5 (Essential): expert start function

int start() {
	if(Bars<100) {
		Log("Bars less than 100");
		return(0);
	}

	CheckGap();
//--------------------------------------------------------
// Section 3A: Define ShortCuts to Common Functions

	bool OpenBar=true;
	if(EnterOpenBar)
		if(iVolume(NULL,0,0)>1)
			OpenBar=false;

	if(!OpenBar)
		return(0);

	LogSeparator1();

	if( TrailingStop>0 && TrailingStart > 0 )
		TrailOrder (TrailingStart, TrailingStop);
	
	int mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
//----------------------------------------------------
// Section 3B: Indicator Calling
	
	double  R = iCustom(NULL,0,"Support and Resistance",0,0);
	double  S = iCustom(NULL,0,"Support and Resistance",1,0);
	double pR = GetPrevR(R);
	double pS = GetPrevS(S);
	
	double BuySignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,0,2);
//	Log("BuySignal="+BuySignal);
	if( BuySignal < 100 ) {
		BuySignal  = 1;
		double SellSignal = 0;
	}
	else {
		BuySignal = 0;
		SellSignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,1,2);
//		Log("SellSignal=",SellSignal);
		if( SellSignal<100 )
			SellSignal = 1;
	}

	Log("Signal:b="+BuySignal+":s="+SellSignal);
	
	AdjustStop(OP_BUY, mktPips,R,S);
	AdjustStop(OP_SELL,mktPips,R,S);

	int MarketCond = -1;
	GetLastMarketCondition(1);
	GetMarketCondition(0);

	LogSeparator2();
//------------------------------------------------
// Section 3C: Entry Conditions

	int BuyCondition=-1, SellCondition=-1;
	bool OpenBuy=false, OpenSell=false;
	int bPips[3], sPips[3];
	int pips.buyD  = MathAbs((Ask-maS)/vPoint);
	int pips.sellD = MathAbs((Bid-maS)/vPoint);

	if( lastDistM < Pips.CompressedMA && pips.MinMax.M > Pips.CompressedMA ) {
//		if( maF>maS && maF>lastMaM )
		if( maF>maS )
			BuyCondition=1;
		else
//		if( maF<maS && maF<lastMaM )
		if( maF<maS )
			SellCondition=1;
		Log("DistM:lastDist="+lastDistM+",currDist="+pips.MinMax.M+
			":FF/F/S="+maFF+"/"+maF+","+lastMaM+"/"+maS+":bC="+BuyCondition+":sC="+SellCondition+
			":a="+Ask+",b="+Bid+",bD="+pips.buyD+",sD="+pips.sellD);
	} else
	if( lastDistS < Pips.CompressedMA && pips.MinMax.S > Pips.CompressedMA ) {
//		if( maM>maSS && maM>lastMaS )
		if( maM>maSS )
			BuyCondition=2;
		else
//		if( maM<maSS && maM<lastMaS )
		if( maM<maSS )
			SellCondition=2;
		Log("DistS:lastDist="+lastDistS+",currDist="+pips.MinMax.S+
			":F/M/S="+maF+"/"+maM+","+lastMaS+"/"+maS+":b="+BuyCondition+":s="+SellCondition+
			":a="+Ask+",b="+Bid+",bD="+pips.buyD+",sD="+pips.sellD);
	} else
	if( lastDistF < Pips.CompressedMA && pips.MinMax.F > Pips.CompressedMA ) {
		// do FFF last intentionally
//		if( maFF>maM && maFF>lastMaF )
		if( maFF>maM )
			BuyCondition=3;
		else
//		if( maFF<maM && maFF<lastMaF )
		if( maFF<maM )
			SellCondition=3;
		Log("DistF:lastDist="+lastDistF+",currDist="+pips.MinMax.F+
			":FF/M="+maFF+"/"+maM+","+lastMaF+":b="+BuyCondition+":s="+SellCondition+
			":a="+Ask+",b="+Bid+",bD="+pips.buyD+",sD="+pips.sellD);
	}
			
	ArrayInitialize(BuyMode,-1); ArrayInitialize(SellMode,-1);
	ArrayInitialize(bEntry,-1);  ArrayInitialize(sEntry,-1);
	ArrayInitialize(bPips,-1);   ArrayInitialize(sPips,-1);
	storeArrayMA(pips.MinMax.F,pips.MinMax.M,pips.MinMax.S, maFF,maF,maM,maS,maSS);

	GetBuyMode (BuyCondition, R, lastMaF);
	GetSellMode(SellCondition,S, lastMaF);
	Log(" (ob="+OP_BUY+",os="+OP_SELL+",bl="+OP_BUYLIMIT+",sl="+OP_SELLLIMIT+",bs="+OP_BUYSTOP+",ss="+OP_SELLSTOP+")");
	
	if( BuyCondition==0 && SellCondition==0 )
		return;

	if( BuyCondition>0 )
		MarketCond = UPTREND;
	else
	if( SellCondition>0 )
		MarketCond = DNTREND;

	Log("MarketCondition="+MarketCond+" (UP="+UPTREND+",uRev="+UPTREND_REVERSAL+",uRtr="+UPTREND_RETRACEMENT+
		",uRnge="+UPRANGE+",rnge="+RANGE+",dRnge="+DNRANGE+
		",DN="+DNTREND+",dRev="+DNTREND_REVERSAL+",dRtr="+DNTREND_RETRACEMENT+")");
	Log("R="+R+",pR="+pR+",S="+S+",pS="+pS);
		
	double LotSize = 0, TradeTP=0;
	bool pipsOk=true;

	if( BuyMode[0]>=0 || BuyMode[1]>=0 || BuyMode[2]>=0 ) {
		GetEntryPrice(BuyCondition, R,S);
//		if( bEntry>0 ) {
			GetExitPrice(BuyCondition, R,S);
	
			OpenBuy = false;
			for(i=0; i<3; i++) {
				if( bExit[i]>0 && 			// no need to match price if limit order
					(BuyMode[i]==OP_BUYLIMIT || !MatchLastOrderPrice(bEntry[i])) ) {
					bPips[i] = GetPips(BuyMode[i],bEntry[i],bExit[i],mktPips);
					if( bPips[i]<0 )
						continue;
					if( BuyMode[i]==OP_BUY )
						bExit[i] = bEntry[i] - (bPips[i]*vPoint);
					if( Pips.Max > 0 && bPips[i] > Pips.Max ) {
						Log(bPips[i]+" < Pips.Max="+Pips.Max);
						pipsOk=false;
					} else
						if(	Pips.Min > 0 && bPips[i] < Pips.Min )
							pipsOk=false;
					if(	pipsOk )
						OpenBuy = true;
//					else
//						OpenBuy = false;
				}
			}
//		}
	} 
	if( SellMode[0]>0 || SellMode[1]>0 || SellMode[2]>0 ) {
		GetEntryPrice(SellCondition, R,S);
//		if( sEntry>0 ) {
			GetExitPrice(SellCondition, R,S);
	
			OpenSell = false;
			for(i=0; i<3; i++) {
				if( sExit[i]>0 && 			// no need to match price if limit order
					(SellMode[i]==OP_SELLLIMIT || !MatchLastOrderPrice(sEntry[i])) ) {
					sPips[i] = GetPips(SellMode[i],sEntry[i],sExit[i],mktPips);
					if( sPips[i]<0 )
						continue;
					if( SellMode[i]==OP_SELL )
						sExit[i] = sEntry[i] + (sPips[i]*vPoint);
					if( Pips.Max > 0 && sPips[i] > Pips.Max ) {
						Log(sPips[i]+" > Pips.Max="+Pips.Max);
						pipsOk=false;
					} else
						if(	Pips.Min > 0 && sPips[i] < Pips.Min )
							pipsOk=false;
					if(	pipsOk )
						OpenSell = true;
//					else
//						OpenSell = false;
				}
			}
//		}
	}

	Log("EntryCond:bc="+BuyCondition+",sc="+SellCondition+",ob="+OpenBuy+",os="+OpenSell+
		":bP="+bPips[0]+","+bPips[1]+","+bPips[2] + ":sP="+sPips[0]+","+sPips[1]+","+sPips[2]);
//-------------------------------------------------
// Section 3D: Close Conditions

	if(!OpenBuy && !OpenSell)
		return(0);
//--------------------------------------------------
// Section 3E: Order Placement
//	Buy at Ask, Sell at Bid

	int expiration=CurTime()+PERIOD_D1*60*3;	// 3 days
	Log("expiration:Exp="+TimeToStr(expiration));
	
	for(i=0; i<3; i++) {
		DebugLog("i="+i+":P="+bPips[i]+","+sPips[i]);
		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenBuy==true) {
			LotSize = GetLots(bPips[i]);
			if( LotSize>0 ) {
				ticket=0;number=0;
				while(ticket<=0 && number<MaxRetry) {
					number = number+1;
					RefreshRates();
					if( BuyMode[i]==OP_BUY ) {
						ticket = OrderSend(Symbol(),OP_BUY,LotSize,
									Ask,vSlippage,bExit[i],TradeTP,MarketCond+":"+EAName, MagicNumber, 0, Green);
					} else
						ticket = OrderSend(Symbol(),BuyMode[i],LotSize,
									bEntry[i],0,bExit[i],TradeTP,MarketCond+":"+EAName, MagicNumber, expiration, Green);
	
					if(ticket<=0) {
						error=GetLastError();
						bPips[i] = NormalizeDouble((Ask-bExit[i])/vPoint,0);
						Log("ERR:OrderSend:"+number+","+error+",oT="+BuyMode[i]+
							",Ask="+bEntry[i]+",sl="+bExit[i]+",tp="+TradeTP+",p="+bPips[i]+",mktP="+mktPips);
						if( error==130 ||
							error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
							break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
						}
						//---- 10 seconds wait
						Sleep(SleepCount);
					} else
						Log("OrderStat:"+MagicNumber+":"+Symbol()+":"+ticket+":"+MarketCond+":"+BuyMode[i]+":"+TradeTP);
//					return (ticket);
				}
			}
		}
	
		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenSell==true) {
			LotSize = GetLots(sPips[i]);
			if(	LotSize>0 ) {
				ticket=0;number=0;
				while(ticket<=0 && number<MaxRetry) {
					number = number+1;
					RefreshRates();
					if( SellMode[i]==OP_SELL ) {
						ticket= OrderSend(Symbol(),OP_SELL, LotSize,
										Bid,vSlippage,sExit[i],TradeTP, MarketCond+":"+EAName, MagicNumber, 0, Red);
					} else
	//				if( SellMode==OP_SELLLIMIT )
	//					ticket= OrderSend(Symbol(),OP_SELLLIMIT, LotSize,
	//									sEntry,0,sExit,TradeTP, EAName, MagicNumber, expiration, Red);
	//				else
	//				if( SellMode==OP_SELLSTOP )
	//					ticket= OrderSend(Symbol(),OP_SELLSTOP, LotSize,
						ticket= OrderSend(Symbol(),SellMode[i], LotSize,
										sEntry[i],0,sExit[i],TradeTP, MarketCond+":"+EAName, MagicNumber, expiration, Red);
	
					if(	ticket<=0 ) {
						error=GetLastError();
						sPips[i] = NormalizeDouble((sExit[i]-Bid)/vPoint,0);
						Log("ERR:OrderSend:"+number+","+error+",oT="+SellMode[i]+
							",Bid="+sEntry[i]+",sl="+sExit[i]+",tp="+TradeTP+",p="+sPips[i]+",mktP="+mktPips);
						if( error==130 ||
							error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
							break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
						}
						//---- 10 seconds wait
						Sleep(SleepCount);
					} else
						Log("OrderStat:"+MagicNumber+":"+Symbol()+":"+ticket+":"+MarketCond+":"+SellMode[i]+":"+TradeTP);
				}
			}
		}
	}
//---------------------------------------------------------
	if(	ticket>0 )
		return(ticket);
// End of start()
	return(0);
}

// Structure #6 (Optional): Custom Functions

int GetPips(int dir, double entryPrice, double exitPrice, int mktP) {
	if( dir<0 )
		return(-1);
	int slPips,tolPips;
	if( dir==OP_BUY || dir==OP_BUYLIMIT || dir==OP_BUYSTOP )
		slPips=(entryPrice - exitPrice) / vPoint;
	else
	if( dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_SELLSTOP )
		slPips=(exitPrice - entryPrice) / vPoint;
	slPips = NormalizeDouble(slPips,0);
	Log("GetPips:et="+entryPrice+",ex="+exitPrice+":minP="+Pips.Min+",P="+slPips);
	if( slPips < Pips.Min )
		return(-1);
	int slPips2 = slPips;
	if( Digits==3 || Digits==5 )
		slPips2 = slPips*10;
	if( slPips2 < mktP && RevisePips==true ) {
		slPips = mktP;
		Log("GetPips:revised slP="+slPips);
	}
	return(slPips);
//	return(NormalizeDouble(slPips,0));
}

double GetLots(int pips) {
	if( pips<0 )
		return(-1);
		
	double leverage  = AccountLeverage();
	double minlot    = MarketInfo(Symbol(), MODE_MINLOT);
//	double maxlot    = MarketInfo(Symbol(), MODE_MAXLOT);
	double lotsize   = MarketInfo(Symbol(), MODE_LOTSIZE);
//	double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL);

	double MinLots = 0.01; double MaximalLots = 50.0;
	double lots = 0;

	if(	(Pips.Min > 0 && pips < Pips.Min) ||
		(Pips.Max > 0 && pips > Pips.Max) )
		return(-1);

	double usdsgdRate = NormalizeDouble(iClose("USDSGD",PERIOD_D1,1),LotDigits);
	double cashAtRisk = NormalizeDouble(AccountFreeMargin() * RiskRatio/100, LotDigits);

	RValue = pips * usdsgdRate;
	double stopCost = RValue * 10;

	lots = NormalizeDouble(cashAtRisk / stopCost, LotDigits);
	double tradeVal = Ask * lots * lotsize / leverage;
	if( Digits==3 )
		tradeVal = tradeVal / 100;
	Log("GetLots:afm="+ NormalizeDouble(AccountFreeMargin(),LotDigits)+":Pips="+pips+">"+Pips.Min+
		":UsdSgd="+usdsgdRate+",CshRisk="+cashAtRisk+",Rval="+RValue+",Lots="+lots+
		",minLots="+minlot+",size="+lotsize+",lev="+leverage+",tradeVal="+tradeVal);
	if(lots < minlot)
	{
		Log("ERRCOND:Insufficient fund:"+ lots+ " + minlot="+ minlot);
		lots = -1;
		return (lots);
	}
	if(lots > MaximalLots) lots = MaximalLots;
	if( AccountFreeMargin() < tradeVal ) {
		Log("ERRCOND:No money:Lots="+ lots+",size="+lotsize+",lev="+leverage+",traveVal="+tradeVal+">Free Margin = "+ AccountFreeMargin());
		lots = -1;
		return (lots);
	}

	return(lots);
}

bool MatchLastOrderPrice(double entryPrice) {
	if( Pips.Match==0 )
		return(false);
	int oTotal = OrdersTotal();
//	Log("MatchLastOrderPrice:"+oTotal);
	if( oTotal<=0 )
		return(false);

	OrderSelect(oTotal-1,SELECT_BY_POS,MODE_TRADES);
	double ooP=OrderOpenPrice();
	double diff=MathAbs(entryPrice - ooP) / vPoint;
	bool retval=false;
	if( diff<Pips.Match )
		retval = true;	// too close to last order entry price
	Log("MatchLastOrderPrice:oTic="+OrderTicket()+",ooP="+ooP+",dif="+diff+":"+retval);
	return(retval);
}

void CancelLastLimitOrder(int dir, double entryPrice) {
	if( Pips.Match==0 )
		return(false);

	bool retval=false;
	
	for(int Counter=1; Counter<=OrdersTotal(); Counter++) {
		if( OrderSelect(Counter-1,SELECT_BY_POS)==true &&
			OrderMagicNumber() == MagicNumber ) {
			if( OrderType()!=dir )
				continue;
			double ooP=OrderOpenPrice();
			double diff=MathAbs(entryPrice - ooP) / vPoint;
			if( diff<=Pips.Match ) {
				Log("CancelLastLimitOrder:"+Counter+":"+":oTic="+OrderTicket()+
					",ooP="+ooP+",pM="+Pips.Match+",dif="+diff);
				if( !OrderDelete(OrderTicket()) )
					Log("CancelLastLimitOrder:ERR="+GetLastError());
				if( IsTesting() )	// speed up test
					break;
			}
		}
	}
	return(retval);
}

void startFile()
{
	int handle;
	handle=FileOpen("gMacD-"+VER+".log."+Day(), FILE_BIN|FILE_READ|FILE_WRITE);
	if(handle<1)
	{
		 Log("can't open file error-"+GetLastError());
		 return(0);
	}
	FileSeek(handle, 0, SEEK_END);
	//---- add data to the end of file
	string str =
	  "----------------------------------------------------------------------------------------------------------------------------------------\n" +
	  "-- gMacD v."+VER+" - Log Starting...                                                                                                  --\n" +
	  "----------------------------------------------------------------------------------------------------------------------------------------\n";
	FileWriteString(handle, str, StringLen(str));
	FileFlush(handle);
	FileClose(handle);
}
void DebugLog(string str) {
	if(!DebugMode)
		return;
	Log(str);
}
void Log(string str)
{
//	str = "["+Day()+"-"+Month()+"-"+Year()+" "+Hour()+":"+Minute()+":"+Seconds()+"] "+str+"\n";
//	if( NewLine)
//		str = str+"\n";

	if(LogToFile)
	{
		int handle=FileOpen("gMacD-"+VER+".log", FILE_BIN|FILE_READ|FILE_WRITE);
		if(handle<1)
		{
			Print("can't open file error-",GetLastError());
			return(0);
		}
		FileSeek(handle, 0, SEEK_END);
		//---- add data to the end of file
		FileWriteString(handle, str, StringLen(str));
		FileFlush(handle);
		FileClose(handle);
	}
	else
	{
		if(Show.Comments)
			Print(str);
	}
}
void comment(int mktCond, string str, int mmFMS) {
	if(!Show.Comments)
		return;

	string condName;
	switch(mktCond) {
		case UPTREND:				condName="UpTrend"; 				break;
		case UPTREND_REVERSAL:		condName="UPTREND REVERSAL"; 		break;
		case UPTREND_RETRACEMENT:	condName="UpTrend Retracement"; 	break;
		case UPRANGE:				condName="UpTrend Range";			break;
		case RANGE:					condName="Range Market";			break;
		case DNRANGE:				condName="DownTrend Range";			break;
		case DNTREND:				condName="DownTrend";				break;
		case DNRANGE:				condName="DownTrend Range";			break;
		case DNTREND_REVERSAL:		condName="DOWNTREND REVERSAL";		break;
		case DNTREND_RETRACEMENT:	condName="DownTrend Retracement";	break;
	}
	if( mktCond==UPTREND_REVERSAL || mktCond==DNTREND_REVERSAL )
		str = "+++ "+condName+" +++:"+str;
	if( mmFMS <= Pips.CompressedMA ) {
		str = str + " <<< COMPRESSED MA >> ";
		Alert(str);
	}
	Comment(condName+":"+str);
}

void CheckGap() {
	//	Safety Measure: Close if gap crossed SL
	if( !GapCheck )
		return;
//	double stopGapBal = NormalizeDouble(AccountBalance() * (RiskRatio+1)/100, LotDigits);
	for(int Counter=1; Counter<=OrdersTotal(); Counter++) {
		if( OrderSelect(Counter-1,SELECT_BY_POS)==true &&
			OrderMagicNumber() == MagicNumber ) {
			if( OrderType()!=OP_BUY && OrderType()!=OP_SELL )
				continue;
			if( OrderType()==OP_BUY && OrderProfit()<0 &&
				Bid < OrderStopLoss() ) {
//				MathAbs(OrderProfit())>stopGapBal ) {
				OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Bid,Digits), vSlippage, Red);
				Log("GAP BRIDGED BUY SL:oTic="+OrderTicket()+",aB="+AccountBalance()+",oP="+OrderProfit()+",oSL="+OrderStopLoss()+",b="+Bid);
				Alert("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit(),",oSL=",OrderStopLoss(),",b=",Bid);
//					Log("GAP BRIDGED BUY SL:oTic="+OrderTicket()+",aB="+AccountBalance()+",sgB="+stopGapBal+",oP="+OrderProfit());
//					Alert("GAP BRIDGED BUY SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
			}
			if( OrderType()==OP_SELL && OrderProfit()<0 &&
				Ask > OrderStopLoss() ) {
//				MathAbs(OrderProfit())>stopGapBal ) {
				OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(Ask,Digits), vSlippage, Red);
				Log("GAP BRIDGED SELL SL:oTic="+OrderTicket()+",aB="+AccountBalance()+",oP="+OrderProfit()+",oSL="+OrderStopLoss()+",b="+Ask);
				Alert("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",oP=",OrderProfit(),",oSL=",OrderStopLoss(),",b=",Ask);
//				Log("GAP BRIDGED SELL SL:oTic="+OrderTicket()+",aB="+AccountBalance()+",sgB="+stopGapBal+",oP="+OrderProfit());
//				Alert("GAP BRIDGED SELL SL:oTic=",OrderTicket(),",aB=",AccountBalance(),",sgB=",stopGapBal,",oP=",OrderProfit());
			}
		}
	}
}

void GetLastMarketCondition(int shift) {
	lastDistF = arrDistF[0];
	lastDistM = arrDistM[0];
	lastDistS = arrDistS[0];
	lastMaF =iMA(NULL, FastMATime, FastMAPeriod,0, FastMAType,PRICE_CLOSE, shift);
/*
	FFastMAShift=shift; FastMAShift=shift; MidMAShift=shift; SlowMAShift=shift; SSlowMAShift=shift;
	GetMarketCondition(1);
	lastMaFF=maFF;
	lastMaF =maF;
	lastMaM =maM;
	lastMaS =maS;
	lastMaSS=maSS;
	Log("lastMA:"+lastMaFF+","+lastMaF+","+lastMaM+","+lastMaS+","+lastMaSS);
	lastDistF = pips.MinMax.F;
	lastDistM = pips.MinMax.M;
	lastDistS = pips.MinMax.S;
	Log("lastDist:"+lastDistF+","+lastDistM+","+lastDistS);
	FFastMAShift=0; FastMAShift=0; MidMAShift=0; SlowMAShift=0; SSlowMAShift=0;
*/
}

void GetMarketCondition(int shift) {
	string str;
	int mktCond=RANGE, pips.pdiff;
	
	maFF=iMA(NULL,FFastMATime,FFastMAPeriod,shift,FFastMAType,PRICE_CLOSE,FFastMAShift);
	maF =iMA(NULL, FastMATime, FastMAPeriod,shift, FastMAType,PRICE_CLOSE, FastMAShift);
	maM =iMA(NULL,  MidMATime,  MidMAPeriod,shift,  MidMAType,PRICE_CLOSE,  MidMAShift);
	maS =iMA(NULL, SlowMATime, SlowMAPeriod,shift, SlowMAType,PRICE_CLOSE, SlowMAShift);
	maSS=iMA(NULL,SSlowMATime,SSlowMAPeriod,shift,SSlowMAType,PRICE_CLOSE,SSlowMAShift);
	normFF=NormalizeDouble(maFF,Digits-1);
	normF =NormalizeDouble(maF, Digits-1);
	normM =NormalizeDouble(maM, Digits-1);
	normS =NormalizeDouble(maS, Digits-1);
	normSS=NormalizeDouble(maSS, Digits-1);
	Log("iMA:"+maFF+","+maF+","+maM+","+maS+","+maSS);
	pips.madiff.FFF= MathAbs((normFF- normF))  / vPoint;
	pips.madiff.FM = MathAbs((normF - normM))  / vPoint;
	pips.madiff.MS = MathAbs((normM - normS))  / vPoint;
	pips.madiff.SSS= MathAbs((normS - normSS)) / vPoint;
	pips.madiff.FFM= MathAbs((normFF- normM))  / vPoint;
	pips.madiff.FS = MathAbs((normF - normS))  / vPoint;
	pips.madiff.MSS= MathAbs((normSS- normM))  / vPoint;
	// FFF
	if( maFF < maF ) {
		pMinF = MathMin(maFF,maM);
		pMaxF = MathMax(maF,maM);
		if( pMaxF==maM ) {
			pMidF = maF;
			pips.MinMax.F = pips.madiff.FFM;
			str="M:"+pips.madiff.FM+":F:"+pips.madiff.FFF+":FF:"+pips.MinMax.F;
		} else
		if( pMinF==maM ) {
			pMidF = maFF;
			pips.MinMax.F = pips.madiff.FM;
			str="F:"+pips.madiff.FFF+":FF:"+pips.madiff.FFM+":M:"+pips.MinMax.F;
		} else {
			pMidF = maM;
			pips.MinMax.F = pips.madiff.FFF;
			str="F:"+pips.madiff.FM+":M:"+pips.madiff.FFM+":FF:"+pips.MinMax.F;
		}
		str="iMA-F:"+str;
	} else {
		pMinF = MathMin(maF,maM);
		pMaxF = MathMax(maFF,maM);
		if( pMaxF==maM ) {
			pMidF = maFF;
			pips.MinMax.F = pips.madiff.FM;
			str="M:"+pips.madiff.FFM+":FF:"+pips.madiff.FFF+":F:"+pips.MinMax.F;
		} else
		if( pMinF==maM ) {
			pMidF = maF;
			pips.MinMax.F = pips.madiff.FFM;
			str="FF:"+pips.madiff.FFF+":F:"+pips.madiff.FM+":M:"+pips.MinMax.F;
		} else {
			pMidF = maM;
			pips.MinMax.F = pips.madiff.FFF;
			str="FF:"+pips.madiff.FFM+":M:"+pips.madiff.FM+":F:"+pips.MinMax.F;
		}
		str="iMA-F:"+str;
	}
	// FMS
	if( maF < maM ) {
		pMinM = MathMin(maF,maS);
		pMaxM = MathMax(maM,maS);
		if( pMaxM==maS ) {
			pMidM = maM;
			pips.MinMax.M = pips.madiff.FS;
			str="S:"+pips.madiff.MS+":M:"+pips.madiff.FM+":F:"+pips.MinMax.M;
		} else
		if( pMinM==maS ) {
			pips.MinMax.M = pips.madiff.MS;
			pMidM = maF; str="M:"+pips.madiff.FM+":F:"+pips.madiff.FS+":S:"+pips.MinMax.M;
		} else {
			pMidM = maS;
			pips.MinMax.M = pips.madiff.FM;
			str="M:"+pips.madiff.MS+":S:"+pips.madiff.FS+":F:"+pips.MinMax.M;
		}
		str="iMA-M:"+str;
	} else {
		pMinM = MathMin(maM,maS);
		pMaxM = MathMax(maF,maS);
		if( pMaxM==maS ) {
			pMidM = maF;
			pips.MinMax.M = pips.madiff.MS;
			str="S:"+pips.madiff.FS+":F:"+pips.madiff.FM+":M:"+pips.MinMax.M;
		} else
		if( pMinM==maS ) {
			pMidM = maM;
			pips.MinMax.M = pips.madiff.FS;
			str="F:"+pips.madiff.FS+":M:"+pips.madiff.MS+":S:"+pips.MinMax.M;
		} else {
			pMidM = maS;
			pips.MinMax.M = pips.madiff.FM;
			str="F:"+pips.madiff.FS+":F:"+pips.madiff.MS+":M:"+pips.MinMax.M;
		}
		str="iMA-M:"+str;
	}
	// SSS
	if( maM < maS ) {
		pMinS = MathMin(maM,maSS);
		pMaxS = MathMax(maS,maSS);
		if( pMaxS==maSS ) {
			pMidS = maS;
			pips.MinMax.S = pips.madiff.MSS;
			str="SS:"+pips.madiff.SSS+":S:"+pips.madiff.MS+":M:"+pips.MinMax.S;
		} else
		if( pMinS==maSS ) {
			pMidS = maM;
			pips.MinMax.S = pips.madiff.SSS;
			str="S:"+pips.madiff.MS+":M:"+pips.madiff.MSS+":SS:"+pips.MinMax.S;
		} else {
			pMidS = maSS;
			pips.MinMax.S = pips.madiff.MS;
			str="S:"+pips.madiff.SSS+":SS:"+pips.madiff.MSS+":M:"+pips.MinMax.S;
		}
		str="iMA-S:"+str;
	} else {
		pMinS = MathMin(maS,maSS);
		pMaxS = MathMax(maM,maSS);
		if( pMaxS==maSS ) {
			pMidS = maM;
			pips.MinMax.S = pips.madiff.SSS;
			str="SS:"+pips.madiff.MSS+":M:"+pips.madiff.MS+":S:"+pips.MinMax.S;
		} else
		if( pMinS==maSS ) {
			pMidS = maS;
			pips.MinMax.S = pips.madiff.MSS;
			str="M:"+pips.madiff.MS+":S:"+pips.madiff.SSS+":SS:"+pips.MinMax.S;
		} else {
			pMidS = maSS;
			pips.MinMax.S = pips.madiff.MS;
			str="M:"+pips.madiff.MSS+":SS:"+pips.madiff.SSS+":S:"+pips.MinMax.S;
		}
		str="iMA-S:"+str;
	}
	Log(str);
}

void GetBuyMode(int buyCond, double r1, double lastVal) {
	double lowVal=-1;
	if( buyCond<0 )
		return;

	int pips.dist = (Ask-r1)/vPoint;
	if( Ask > r1 && pips.dist > Pips.CompressedMA )
		BuyMode[0] = OP_BUY;
//	else {
//		lowVal = iLow(Symbol(), PERIOD_H4, 1);
		lowVal = Low[1];
		if( lowVal < lastVal )
			BuyMode[0] = OP_BUY;
		else {
			BuyMode[1] = OP_BUYSTOP;
			BuyMode[2] = OP_BUYLIMIT;
		}
//	}
	Log("GetBuyMode:bm="+BuyMode[0]+","+BuyMode[1]+","+BuyMode[2]+":lV="+lowVal+","+lastVal+":pd="+pips.dist+","+Pips.CompressedMA);
}

void GetSellMode(int sellCond, double s1, double lastVal) {
	double highVal=-1;
	if( sellCond<0 )
		return;

	int pips.dist = (s1-Bid)/vPoint;
	if( Bid < s1 && pips.dist > Pips.CompressedMA )
		SellMode[0] = OP_SELL;
//	else {
//		highVal = iHigh(Symbol(), PERIOD_H4, 1);
		highVal = High[1];
		if( highVal > lastVal )
			SellMode[0] = OP_SELL;
		else {
			SellMode[1] = OP_SELLSTOP;
			SellMode[2] = OP_SELLLIMIT;
		}
//	}
	Log("GetSellMode:sm="+SellMode[0]+","+SellMode[1]+","+SellMode[2]+":hV="+highVal+","+lastVal+":pd="+pips.dist+","+Pips.CompressedMA);
}

void GetEntryPrice(int tradeCond, double r1, double s1) {
	if( BuyMode[0] == OP_BUY )
		bEntry[0] = Ask;
	else 
	if( SellMode[0] == OP_SELL )
		sEntry[0] = Bid;

	if( BuyMode[1] == OP_BUYSTOP ) {
		if( r1>Ask )
			bEntry[1] = r1 + (Pips.BuyStop_Entry*vPoint);
		else
			bEntry[1] = Ask + (4*Pips.BuyStop_Entry*vPoint);
	} else 
	if( SellMode[1] == OP_SELLSTOP ) {
		if( s1<Bid )
			sEntry[1] = s1 - (Pips.SellStop_Entry*vPoint);
		else
			sEntry[1] = Bid - (4*Pips.SellStop_Entry*vPoint);
	}
	
	if( BuyMode[2] == OP_BUYLIMIT ) {
		if( tradeCond==1 )
			bEntry[2] = maM;
		else
		if( tradeCond==2 )
			bEntry[2] = maS;
		else
			bEntry[2] = maF;
	} else
	if( SellMode[2] == OP_SELLLIMIT ) {
		if( tradeCond==1 )
			sEntry[2] = maM;
		else
		if( tradeCond==2 )
			sEntry[2] = maS;
		else
			sEntry[2] = maF;
	}
	bEntry[0] = NormalizeDouble(bEntry[0],Digits);
	sEntry[0] = NormalizeDouble(sEntry[0],Digits);
	bEntry[1] = NormalizeDouble(bEntry[1],Digits);
	sEntry[1] = NormalizeDouble(sEntry[1],Digits);
	bEntry[2] = NormalizeDouble(bEntry[2],Digits);
	sEntry[2] = NormalizeDouble(sEntry[2],Digits);
	Log("GetEntryPrice:tC="+tradeCond+":b="+bEntry[0]+","+bEntry[1]+","+bEntry[2]+":s="+sEntry[0]+","+sEntry[1]+","+sEntry[2]
		+":bs="+Pips.BuyStop_Entry+",ss="+Pips.SellStop_Entry);
}

void GetExitPrice(int tradeCond, double r1, double s1) {
	int pips.distance=-1;
	
	if( BuyMode[0] == OP_BUY ) {
		if( tradeCond==1 )
			bExit[0] = maM;
		else
		if( tradeCond==2 )
			bExit[0] = maS;
		else
			bExit[0] = maF;
	} else
	if( SellMode[0] == OP_SELL ) {
		if( tradeCond==1 )
			sExit[0] = maM;
		else
		if( tradeCond==2 )
			sExit[0] = maS;
		else
			sExit[0] = maF;
	}

	if( BuyMode[1] == OP_BUYSTOP ) {
		bExit[1] = r1;
	} else
	if( SellMode[1] == OP_SELLSTOP ) {
		sExit[1] = s1;
	}

	if( BuyMode[2] == OP_BUYLIMIT ) {
		bExit[2] = s1;
		if( (bEntry[2]-s1)/vPoint > Pips.BuyLimit_SL )
			bExit[2] = (bEntry[2]+s1)/2;
	} else
	if( SellMode[2] == OP_SELLLIMIT ) {
		sExit[2] = r1;
		if( (r1-sEntry[2])/vPoint > Pips.SellLimit_SL )
			bExit[2] = (sEntry[2]+s1)/2;
	}
	
	bExit[0] = NormalizeDouble(bExit[0],Digits);
	sExit[0] = NormalizeDouble(sExit[0],Digits);
	bExit[1] = NormalizeDouble(bExit[1],Digits);
	sExit[1] = NormalizeDouble(sExit[1],Digits);
	bExit[2] = NormalizeDouble(bExit[2],Digits);
	sExit[2] = NormalizeDouble(sExit[2],Digits);

	Log("GetExitPrice:b="+bExit[0]+","+bExit[1]+","+bExit[2]+":s="+bExit[0]+","+bExit[1]+","+bExit[2]
		+":bl="+Pips.BuyLimit_SL+",sl="+Pips.SellLimit_SL);
}

double GetHighestR(double rVal) {
	int i=3,found=1;
	double lastVal=rVal, pVal=rVal, hVal=rVal;
	while(found<Count.HighR && i<100) {
		i = i+3;
		pVal = iCustom(NULL,0,"Support and Resistance",0,i);
		if( pVal==lastVal || MathAbs((pVal-lastVal)/vPoint)<3)
			continue;
		found = found + 1;
		if( pVal > hVal )
			hVal = pVal;
		lastVal = pVal;
		Log("GetHighR:i="+found+",pVal="+pVal+",hVal="+hVal);
	}
	if( found<Count.HighR ) {
		Log("GetHighR:found="+found);
		return(-1);
	}
	return(hVal);
}

double GetLowestS(double val) {
	int i=3,found=1;
	double lastVal = val, pVal = val, lVal = val;
	while(found<Count.LowS && i<100) {
		i = i+3;
		pVal = iCustom(NULL,0,"Support and Resistance",1,i);
		if( pVal==lastVal || MathAbs((pVal-lastVal)/vPoint)<3)
			continue;
		found = found + 1;
		if( pVal < lVal )
			lVal = pVal;
		lastVal = pVal;
		Log("GetLowS:i="+found+",pVal="+pVal+",lVal="+lVal);
	}
	if( found<Count.LowS ) {
		Log("GetLowS:found="+found);
		return(-1);
	}
	return(lVal);
}

double GetPrevR(double val) {
	return(GetPrevSR(0,val));
}
double GetPrevS(double val) {
	return(GetPrevSR(1,val));
}
double GetPrevSR(int SR,double val) {
	int i=3;
	double pVal = val;
	while( MathAbs((pVal-val)/vPoint)<3 && i<20) {
		i=i+3;
		pVal = iCustom(NULL,0,"Support and Resistance",SR,i);
//		Log("i="+i+",R="+R+",pR="+pR);
	}
	return(pVal);
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

		if( oType<=OP_SELL && OrderSymbol()==Symbol()
			&& OrderMagicNumber()==MagicNumber) {

//			Log("TrailOrder:"+oTotal+":"+OType+":"+Trailingstart+":"+Trailingstop);

			if(oType==OP_BUY) {
				if(Ask> NormalizeDouble(ooPrice+TrailingStart* vPoint,Digits)
					&& tStopLoss < NormalizeDouble(Bid-(TrailingStop+TrailingStep)*vPoint,Digits)) {
					tStopLoss = NormalizeDouble(Bid-TrailingStop*vPoint,Digits);
					ticket = OrderModify(oTicket,ooPrice,tStopLoss,OrderTakeProfit(),0,Blue);
					if (ticket > 0) {
						Log("TrailingStop #1 Activated: "+ OrderSymbol()+ ": SL"+ tStopLoss+ ": Bid"+ Bid);
						continue;
					}
				}
			}

			if (oType==OP_SELL) {
				if (Bid < NormalizeDouble(ooPrice-TrailingStart*vPoint,Digits)
					&& (sl >(NormalizeDouble(Ask+(TrailingStop+TrailingStep)*vPoint,Digits)))
					|| (OrderStopLoss()==0)) {
					tStopLoss = NormalizeDouble(Ask+TrailingStop*vPoint,Digits);
					ticket = OrderModify(oTicket,OrderOpenPrice(),tStopLoss,OrderTakeProfit(),0,Red);
					if (ticket > 0)
					{
						Log("Trailing #2 Activated: "+ OrderSymbol()+ ": SL "+tStopLoss+ ": Ask "+ Ask);
//						return(0);
					}
				}
			}
		}
	}
}

void AdjustStop(int dir, int mktPips, double R, double S)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if( oTotal<=0 )
		return;

	LogSeparator2();
	Log("AdjustStop1:"+dir+" (ob=0,os=1,bl=2,sl=3,bs=4,ss=5)"+",oT="+oTotal);

	double bSL=-1, sSL=-1;
	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		int ticket=0,oType=OrderType();
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber ) {
			Log("AdjustStop1:Abort oTic="+oTicket);
			continue;
		}
		if( oType!=dir || oType>1 ) {
			Log("AdjustStop2:Abort oTic="+oTicket+",oT="+oType);
			continue;
		}
		if( OrderProfit()<=0 ) {
			Log("AdjustStop3:Abort oTic="+oTicket);
			continue;
		}

		double ooPrice = OrderOpenPrice(), oSL=OrderStopLoss();
		int oMC = StringGetChar(OrderComment(),0) - 48;
//		int oTM = StringGetChar(OrderComment(),1) - 48;
		if( oType==OP_BUY && S > oSL )
			bSL = S;
		else
		if( oType==OP_SELL && R < oSL )
			sSL = R;
		else {
			Log("AdjustStop4:Abort oTic="+oTicket+",oMC="+oMC+",oT="+oType+",oSL="+bSL+","+sSL+",R="+R+",S="+S);
			continue;
		}
				
		ticket=0;
		int number=0,pips;
		double SL;
		while( ticket<=0 && number<MaxRetry ) {
			number = number+1;
			RefreshRates();
			if( oType==OP_BUY )
				SL = bSL;
//				pips = NormalizeDouble((Ask-bSL)/vPoint,0);
			else
				SL = sSL;
//				pips = NormalizeDouble((sSL-Bid)/vPoint,0);
//			if( pips > mktPips || number==MaxRetry ) {
				ticket = OrderModify(oTicket,ooPrice,SL,OrderTakeProfit(),0,Blue);
				if(ticket>0)
					Log("AdjustStopModify:Dir="+dir+",oTic="+oTicket+",oMC="+oMC+",nTic="+ticket+
							",OOP="+ooPrice+",SL="+ SL+",Ask="+Ask+",Bid="+Bid+",bal="+AccountBalance());
				else {
					error=GetLastError();
					if( oType==OP_BUY )
						pips = NormalizeDouble((Ask-bSL)/vPoint,0);
					else
						pips = NormalizeDouble((sSL-Bid)/vPoint,0);
					Log("ERR:OrderModify:"+number+","+error+",oT="+oType+",Ask="+Ask+",Bid="+Bid
							+",sl="+SL+",p="+pips+",mktP="+mktPips);
//					if( error==130 )
					if( error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
						break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
					}
					//---- 10 seconds wait
					Sleep(SleepCount);
				}
//			} else {
//					Log("OrderModify:oTic="+oTicket+":retry "+number+":oT="+oType+
//						",Ask="+Ask+",Bid="+Bid+",sl="+SL+",p="+pips+",mktP="+mktPips);
//					Sleep(SleepCount);
//			}
		}
		
		if( SL!=ooPrice && PartialClosePortion>0 ) {
			double cLots = NormalizeDouble(OrderLots()/PartialClosePortion,2);
			if( cLots>0 ) {
				double halfProfit;
				if( oType==OP_BUY ) {
					halfProfit = oSL + (OrderTakeProfit() - oSL) / 2;
					if( Bid >= halfProfit ) {
						OrderClose(oTicket,cLots,Bid,vSlippage,Red);
//						Log("LE="+GetLastError());
					}
				} else
				if( oType==OP_SELL ) {
					halfProfit = oSL - (oSL - OrderTakeProfit()) / 2;
					if( Ask <= halfProfit ) {
						OrderClose(oTicket,cLots,Ask,vSlippage,Red);
//						Log("LE="+GetLastError());
					}
				}
				Log("PartialClose:oTic="+oTicket+",cL="+cLots+",hp="+halfProfit+",a="+Ask+",b="+Bid+
						",sl="+oSL+",tp="+OrderTakeProfit()+",bal="+AccountBalance());
			}
		}
	}
	
	LogSeparator2();
}

double GetStopLoss(int dir,double R,double pR,double S,double pS) {
	double stopLoss;
	if( dir==OP_BUY || dir==OP_BUYLIMIT ) {
		stopLoss = Low[iLowest(Symbol(), 0, MODE_LOW, StopLossBarCount, 1)];
//		Log("GetStopLoss:"+stopLoss);
		if( R<pR && S<pS )
			stopLoss = stopLoss - (Pips.BUY_Tol*vPoint);
	} else {
//	if( dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_BUYSTOP ) {
		stopLoss = High[iHighest(Symbol(), 0, MODE_HIGH, StopLossBarCount, 1)];
//		Log("GetStopLoss:"+stopLoss);
		if( R>pR && S>pS )
			stopLoss = stopLoss + (Pips.SELL_Tol*vPoint);
	}
	Log("GetStopLoss:dir="+dir+",bar="+StopLossBarCount+":pB="+Pips.BUY_Tol+":pS="+Pips.SELL_Tol+":sl="+stopLoss);
	return(stopLoss);
}

void LogSeparator1() {
	Log("================================================================================================");
}
void LogSeparator2() {
	Log("------------------------------------------------------------------------------------------------");
}
void LogSeparatorStart() {
	Log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ v"+VER+" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
}
void LogSeparatorEnd() {
	Log("________________________________________________________________________________________________");
}

// Section 4A: Close Function

void close(int type)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if(oTotal<=0)
		return;

	Log("close:oT="+type+":count="+oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		double oLots = OrderLots();
		int oType = OrderType();
		int oMC = StringGetChar(OrderComment(),0) - 48;
		Log("close:count="+Counter+":"+OrderSymbol()+":"+oTicket+":"+oMC+":"+oType+":"+OrderMagicNumber());
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber )
			continue;
		RefreshRates();
		if(type==OP_BUY && oType==OP_BUY){
//			if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
//				RefreshRates();
				OrderClose(oTicket,oLots,NormalizeDouble(Bid,Digits), vSlippage);
//				Comment("Close ",oTicket,":",oLots,"lots at bid=",Bid);
//			}
		}
		if(type==OP_SELL && oType==OP_SELL){
//			if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) {
//				RefreshRates();
				OrderClose(oTicket,oLots,NormalizeDouble(Ask,Digits),vSlippage);
//				Comment("Close ",oTicket,":",oLots,"lots at ask=",Ask);
//			}
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

void initMA() {
	static double arrMA[5][5], arrDist[5];
	static double arrMaF[5][3], arrDistF[5], arrMaM[5][3], arrDistM[5], arrMaS[5][3], arrDistS[5];
	for(i=0; i<5; i++) {
		arrDistF[i]=-1;
		arrDistM[i]=-1;
		arrDistS[i]=-1;
		for(int j=0; j<3; j++) {
			arrMaF[i][j] = -1;
			arrMaM[i][j] = -1;
			arrMaS[i][j] = -1;
		}
	}
	for(i=0; i<5; i++) {
		InitMarketCondition(i);
		GetMarketCondition(0);
		storeArrayMA(pips.MinMax.F,pips.MinMax.M,pips.MinMax.S, maFF,maF,maM,maS,maSS);
	}
	InitMarketCondition(0);
}
void storeArrayMA(int dist1,int dist2,int dist3, double ma1, double ma2, double ma3, double ma4, double ma5) {
	// shift all by one first to keep only last 5
	for( int i=4; i>0; i-- ) {
		arrDistF[i] = arrDistF[i-1];
		arrDistM[i] = arrDistM[i-1];
		arrDistS[i] = arrDistS[i-1];
		for( int j=4; j>0; j-- ) {
//			DebugLog("storeArrayMA:"+i+","+j+":"+arrMaF[i][j]+","+arrMaM[i][j]+","+arrMaS[i][j]);
			arrMaF[i][j] = arrMaF[i][j-1];
			arrMaM[i][j] = arrMaM[i][j-1];
			arrMaS[i][j] = arrMaS[i][j-1];
		}
	}
	arrDistF[0]  = dist1;
	arrDistM[0]  = dist2;
	arrDistS[0]  = dist3;
	arrMaF[0][0] = ma1; arrMaF[0][1] = ma2; arrMaF[0][2] = ma3;
	arrMaM[0][0] = ma2; arrMaM[0][1] = ma3; arrMaM[0][2] = ma4;
	arrMaS[0][0] = ma3; arrMaS[0][1] = ma4; arrMaS[0][2] = ma5;
}

void InitMarketCondition(int period) {
	FFastMAShift=period;
	 FastMAShift=period;
	  MidMAShift=period;
	 SlowMAShift=period;
	SSlowMAShift=period;
}

