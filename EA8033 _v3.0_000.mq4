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

#define VER "3.0"

// Structure #2 (Optional): Input parameters
extern double MagicNumber = 8033;
extern int TimeFrame = 240;

//extern bool MM = TRUE;
extern double RiskRatio = 2;
extern int ConcurrentOrders = 0;	// 0=no limit
extern int Count.HighR = 5;
extern int Count.LowS  = 5;
//extern int StopPC.BuyLimit  = 5;
//extern int StopPC.SellLimit = 5;

extern int Pips.Min = 10;
extern int Pips.Max = 150;
extern int Pips.Match = 0;			// 0 = no check
extern int Pips.BuyTrend.Margin = 20;
extern int Pips.SellTrend.Margin = 20;
extern int Pips.BUY_Tol = 10;		// 0=no extra pips
extern int Pips.SELL_Tol = 10;
extern int Pips.CompressedMA = 5;

extern double LotDigits =2;
extern int StopLossBarCount = 1;
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
extern int Pips.BS_Tol = 0;
extern int Pips.SS_Tol = 0;
//extern bool MAFilterRev = false;
//extern int MATime = 0;
//extern int MAPeriod = 50;
//extern int MAMethod=1;
//extern int MAShift=1;

extern int FFastMATime   = 0;
extern int FFastMAPeriod = 21;
extern int FFastMAType   = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FFastMAPrice  = 0;
extern int FFastMAShift  = 0;
//---------------------
extern int FastMATime    = 0;
extern int FastMAPeriod  = 34;
extern int FastMAType    = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FastMAPrice   = 0;
extern int FastMAShift   = 0;
//---------------------
extern int MidMATime     = 0;
extern int MidMAPeriod   = 89;
extern int MidMAType     = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int MidMAPrice    = 0;
extern int MidMAShift    = 0;
//---------------------
extern int SlowMATime    = 0;
extern int SlowMAPeriod  = 200;
extern int SlowMAType    = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int SlowMAPrice   = 0;
extern int SlowMAShift   = 0;

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
static string EAName = "t.roy";

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

int BuyMode=-1, SellMode=-1, MaxRetry=10, SleepCount=10000;
int Counter, vSlippage, error;
double ticket, number, vPoint, RValue, pMin,pMid,pMax;
double mafilterF,mafilterM,mafilterS,mafilterFF;
double normF,normM,normS,normFF;
int pips.madiff.FM, pips.madiff.MS, pips.madiff.FS, pips.madiff.FF, pips.MinMax;
bool DebugMode=false;

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
	
	double  R = iCustom(NULL,0,"Support and Resistance",0,0);
	double  S = iCustom(NULL,0,"Support and Resistance",1,0);
	double pR = GetPrevR(R);
	double pS = GetPrevS(S);
	Log("Barry:R="+R+",pR="+pR+",S="+S+",pS="+pS);
	
	int mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
	int MarketCond = GetMarketCondition(R,S,pR,pS);
	
	AdjustStop(OP_BUY,mktPips,R,S);
	AdjustStop(OP_SELL,mktPips,R,S);

//----------------------------------------------------
// Section 3B: Indicator Calling

	bool OpenBuy=false, OpenSell=false;
	bool BuyCondition = false, SellCondition = false;

	double BuySignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,0,2);
//	Log("BuySignal="+BuySignal);
	if( BuySignal < 100 ) {
		BuyCondition=true;
	}
	else {
		double SellSignal = iCustom(NULL,0,"G#MACD_Divergence",separator2,
				  FastEMA,FFastEMA,FFFastEMA,
				  SlowEMA,SSlowEMA,SSSlowEMA,
				  SignalSMA,SSignalSMA,SSSignalSMA,
				  separator3,drawIndicatorTrendLines,drawPriceTrendLines,displayAlert,1,2);
//		Log("SellSignal=",SellSignal);
		if( SellSignal<100 )
			SellCondition=true;
	}

	DebugLog("Signal:b="+BuySignal+","+BuyCondition+":s="+SellSignal+","+SellCondition);
	
	if( !BuyCondition && !SellCondition )
		return(0);

	LogSeparator2();
//------------------------------------------------
// Section 3C: Entry Conditions
	
	GetTradeMode(MarketCond, BuyCondition, SellCondition, R,S);
	
	double LotSize = 0, TradeTP, bEntry, bExit, sEntry, sExit;
	int bPips=0, sPips=0;
	bool pipsOk=true;

	if( BuyMode>=0 ) {
		bEntry = GetEntryPrice(MarketCond, BuyMode, R,pR,S,pS);
		if( bEntry>0 ) {
			bExit  = GetExitPrice(MarketCond, BuyMode, bEntry, R,pR,S,pS);
	
			if( bExit>0 && 			// no need to match price if limit order
				(BuyMode==OP_BUYLIMIT || !MatchLastOrderPrice(bEntry)) ) {
				bPips = GetPips(BuyMode,bEntry,bExit,mktPips);
				if( BuyMode==OP_BUY )
					bExit = bEntry - (bPips*vPoint);
				if( Pips.Max > 0 && bPips > Pips.Max ) {
					Log(bPips+" < Pips.Max="+Pips.Max);
					pipsOk=false;
				} else
					if(	Pips.Min > 0 && bPips < Pips.Min )
						pipsOk=false;
				if(	pipsOk )
					OpenBuy = true;
				else
					OpenBuy = false;
			}
		}
	} 
	if( SellMode>0 ) {
		sEntry = GetEntryPrice(MarketCond, SellMode, R,pR,S,pS);
		if( sEntry>0 ) {
			sExit  = GetExitPrice(MarketCond, SellMode, sEntry, R,pR,S,pS);
	
			if( sExit>0 && 			// no need to match price if limit order
				(SellMode==OP_SELLLIMIT || !MatchLastOrderPrice(sEntry)) ) {
				sPips = GetPips(SellMode,sEntry,sExit,mktPips);
				if( SellMode==OP_SELL )
					sExit = sEntry + (sPips*vPoint);
				if( Pips.Max > 0 && sPips > Pips.Max ) {
					Log(sPips+" > Pips.Max="+Pips.Max);
					pipsOk=false;
				} else
					if(	Pips.Min > 0 && sPips < Pips.Min )
						pipsOk=false;
				if(	pipsOk )
					OpenSell = true;
				else
					OpenSell = false;
			}
		}
	}

	Log("EntryCond:bc="+BuyCondition+",sc="+SellCondition+",ob="+OpenBuy+",os="+OpenSell);
	Log("R="+R+",S="+S+","+bExit+","+sExit+":P="+bPips+","+sPips);
//-------------------------------------------------
// Section 3D: Close Conditions

	if( MarketCond==UPTREND_REVERSAL )
		close(OP_BUY);
	else
	if( MarketCond==DNTREND_REVERSAL )
		close(OP_SELL);

	if(!OpenBuy && !OpenSell)
		return(0);
//--------------------------------------------------
// Section 3E: Order Placement
//	Buy at Ask, Sell at Bid

	int expiration=0;
	if( BuyMode!=OP_BUY && SellMode!=OP_SELL ) {
		if( BuyMode==OP_BUYLIMIT && MarketCond==DNTREND ||
			SellMode==OP_SELLLIMIT && MarketCond==UPTREND )
			expiration=CurTime()+PERIOD_D1*60*10;	// 10 days to catch reversal
		else
			expiration=CurTime()+PERIOD_D1*60*5;	// 5 days
		Log("expiration:mC="+MarketCond+",Exp="+TimeToStr(expiration));
	}
	
	while(true) {
		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenBuy==true) {
			LotSize = GetLots(bPips);
			if( LotSize>0 ) {
				if( BuyMode==OP_BUYLIMIT ) {
					if( MarketCond==DNTREND ) {
						CancelLastLimitOrder(BuyMode,bEntry);
						TradeTP=mafilterF;
					} else
					if( MarketCond==UPTREND_REVERSAL ) {
						if( mafilterM > mafilterS )
							TradeTP = mafilterM + (S-bEntry);
						else
							TradeTP = mafilterS + (S-bEntry);
					}
				}
				
				ticket=0;number=0;
				while(ticket<=0 && number<MaxRetry) {
					number = number+1;
					RefreshRates();
					if( BuyMode==OP_BUY ) {
						ticket = OrderSend(Symbol(),OP_BUY,LotSize,
									Ask,vSlippage,bExit,TradeTP,MarketCond+":"+EAName, MagicNumber, 0, Green);
					} else
						ticket = OrderSend(Symbol(),BuyMode,LotSize,
									bEntry,0,bExit,TradeTP,MarketCond+":"+EAName, MagicNumber, expiration, Green);
	
					if(ticket<=0) {
						error=GetLastError();
						bPips = NormalizeDouble((Ask-bExit)/vPoint,0);
						Log("ERR:OrderSend:"+number+","+error+",oT="+BuyMode+
							",Ask="+bEntry+",sl="+bExit+",tp="+TradeTP+",p="+bPips+",mktP="+mktPips);
						if( error==130 ||
							error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
							break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
						}
						//---- 10 seconds wait
						Sleep(SleepCount);
					} else
						Log("OrderStat:"+Symbol()+":"+ticket+":"+MarketCond+":"+BuyMode+":"+TradeTP);
//					return (ticket);
				}
			}
		}

		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenSell==true) {
			LotSize = GetLots(sPips);
			if(	LotSize<=0 )
				break;

			if(	SellMode==OP_SELLLIMIT) {
				if( MarketCond==UPTREND ) {
					CancelLastLimitOrder(SellMode,sEntry);
					TradeTP=mafilterF;
				} else
				if( MarketCond==DNTREND_REVERSAL ) {
					if( mafilterM > mafilterS )
						TradeTP = mafilterS - (sEntry - R);
					else
						TradeTP = mafilterS - (sEntry - R);
				}
			}
			
			ticket=0;number=0;
			while(ticket<=0 && number<MaxRetry) {
				number = number+1;
				RefreshRates();
				if( SellMode==OP_SELL ) {
					ticket= OrderSend(Symbol(),OP_SELL, LotSize,
									Bid,vSlippage,sExit,TradeTP, MarketCond+":"+EAName, MagicNumber, 0, Red);
				} else
//				if( SellMode==OP_SELLLIMIT )
//					ticket= OrderSend(Symbol(),OP_SELLLIMIT, LotSize,
//									sEntry,0,sExit,TradeTP, EAName, MagicNumber, expiration, Red);
//				else
//				if( SellMode==OP_SELLSTOP )
//					ticket= OrderSend(Symbol(),OP_SELLSTOP, LotSize,
					ticket= OrderSend(Symbol(),SellMode, LotSize,
									sEntry,0,sExit,TradeTP, MarketCond+":"+EAName, MagicNumber, expiration, Red);

				if(	ticket<=0 ) {
					error=GetLastError();
//					mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
					sPips = NormalizeDouble((sExit-Bid)/vPoint,0);
					Log("ERR:OrderSend:"+number+","+error+",oT="+SellMode+
						",Bid="+sEntry+",sl="+sExit+",tp="+TradeTP+",p="+sPips+",mktP="+mktPips);
					if( error==130 ||
						error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
						break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
					}
					//---- 10 seconds wait
					Sleep(SleepCount);
				} else
					Log("OrderStat:"+Symbol()+":"+ticket+":"+MarketCond+":"+SellMode+":"+TradeTP);
//				return (ticket);
			}
		}

//		Log("TP="+TradeTP);
		break;
	}
//---------------------------------------------------------
	if(	ticket>0 )
		return(ticket);
// End of start()
	return(0);
}

// Structure #6 (Optional): Custom Functions

int GetPips(int dir, double entryPrice, double exitPrice, int mktP) {
	int slPips,tolPips;
	if( dir==OP_BUY || dir==OP_BUYLIMIT || dir==OP_BUYSTOP )
		slPips=(entryPrice - exitPrice) / vPoint;
	else
	if( dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_SELLSTOP )
		slPips=(exitPrice - entryPrice) / vPoint;
/*
	if( dir==OP_BUY && Pips.BUY_Tol>0 ) {
		tolPips = Pips.BUY_Tol;
		slPips = slPips + tolPips;
	}
	if( dir==OP_SELL && Pips.SELL_Tol>0 ) {
		tolPips = Pips.SELL_Tol;
		slPips = slPips + tolPips;
	}
*/
	slPips = NormalizeDouble(slPips,0);
	Log("GetPips:et="+entryPrice+",ex="+exitPrice+":minP="+Pips.Min+",P="+slPips);
	if( slPips < Pips.Min )
		return(-1);
	if( slPips < mktP && RevisePips==true ) {
		slPips = mktP;
		Log("GetPips:revised slP="+slPips);
	}
	return(slPips);
//	return(NormalizeDouble(slPips,0));
}

double GetLots(int pips) {
	double leverage  = AccountLeverage();
	double minlot    = MarketInfo(Symbol(), MODE_MINLOT);
//	double maxlot    = MarketInfo(Symbol(), MODE_MAXLOT);
	double lotsize   = MarketInfo(Symbol(), MODE_LOTSIZE);
//	double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL);

	double MinLots = 0.01; double MaximalLots = 50.0;
	double lots = 0;

//	if(MM) {
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
		Log("GetLots:"+ NormalizeDouble(AccountFreeMargin(),LotDigits)+":Pips="+pips+">"+Pips.Min+
			":UsdSgd="+usdsgdRate+",CshRisk="+cashAtRisk+",Rval="+RValue+",Lots="+lots+
			",minLots="+minlot+",size="+lotsize+",lev="+leverage+",traveVal="+tradeVal);
//		Comment("MM:", NormalizeDouble(AccountFreeMargin(),LotDigits),":Pips=",pips,">",Pips.Min,
//			":UsdSgd=",usdsgdRate,",CshRisk=",cashAtRisk,",Rval=",RValue,",Lots=",lots);

//		lots = NormalizeDouble(AccountFreeMargin() * RiskRatio/100 / 1000.0, LotDigits);
//		if(lots < minlot) lots = minlot;
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
//	}
//	else
//		lots=NormalizeDouble(Lots,Digits);

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
void comment(int mktCond, string str, int minmax) {
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
	if( minmax <= Pips.CompressedMA ) {
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

int GetMarketCondition(double R, double S, double pR, double pS) {
//	if(	MAFilter<=0 )
//		return(-1);
	string str;
	int mktCond=RANGE, pips.pdiff;
	
	mafilterFF=iMA(NULL,FFastMATime,FFastMAPeriod,0,FFastMAType,PRICE_CLOSE,FFastMAShift);
	mafilterF =iMA(NULL, FastMATime, FastMAPeriod,0, FastMAType,PRICE_CLOSE, FastMAShift);
	mafilterM =iMA(NULL,  MidMATime,  MidMAPeriod,0,  MidMAType,PRICE_CLOSE,  MidMAShift);
	mafilterS =iMA(NULL, SlowMATime, SlowMAPeriod,0, SlowMAType,PRICE_CLOSE, SlowMAShift);
	normFF=NormalizeDouble(mafilterFF,Digits-1);
	normF =NormalizeDouble(mafilterF, Digits-1);
	normM =NormalizeDouble(mafilterM, Digits-1);
	normS =NormalizeDouble(mafilterS, Digits-1);
	pips.madiff.FM = MathAbs((normF - normM)) / vPoint;
	pips.madiff.MS = MathAbs((normM - normS)) / vPoint;
	pips.madiff.FS = MathAbs((normF - normS)) / vPoint;
	pips.madiff.FF = MathAbs((normFF- normF)) / vPoint;
	if( mafilterF < mafilterM ) {
		pMin = MathMin(mafilterF,mafilterS);
		pMax = MathMax(mafilterM,mafilterS);
		if( pMax==mafilterS ) {
			pips.MinMax = pips.madiff.FS;
			pMid = mafilterM; str="S:"+pips.madiff.MS+":M:"+pips.madiff.FM+":F:"+pips.madiff.FS+":FS:"+pips.MinMax;
			Log("GetMarketCondition:iMA:S="+mafilterS+",M="+mafilterM+",F="+mafilterF+":a="+Ask+",b="+Bid);
		} else
		if( pMin==mafilterS ) {
			pips.MinMax = pips.madiff.MS;
			pMid = mafilterF; str="M:"+pips.madiff.FM+":F:"+pips.madiff.FS+":S:"+pips.madiff.MS+":MS:"+pips.MinMax;
			Log("GetMarketCondition:iMA:M="+mafilterM+",F="+mafilterF+",S="+mafilterS+":a="+Ask+",b="+Bid);
		} else {
			pips.MinMax = pips.madiff.FM;
			pMid = mafilterS; str="M:"+pips.madiff.MS+":S:"+pips.madiff.FS+":F:"+pips.madiff.FM+":FM:"+pips.MinMax;
			Log("GetMarketCondition:iMA:M="+mafilterM+",S="+mafilterS+",F="+mafilterF+":a="+Ask+",b="+Bid);
		}
	} else {
		pMin = MathMin(mafilterM,mafilterS);
		pMax = MathMax(mafilterF,mafilterS);
		if( pMax==mafilterS ) {
			pips.MinMax = pips.madiff.MS;
			pMid = mafilterF; str="S:"+pips.madiff.FS+":F:"+pips.madiff.FM+":M:"+pips.madiff.MS+":FM:"+pips.MinMax;
			Log("GetMarketCondition:iMA:S="+mafilterS+",F="+mafilterF+",M="+mafilterM+":a="+Ask+",b="+Bid);
		} else
		if( pMin==mafilterS ) {
			pips.MinMax = pips.madiff.FS;
			pMid = mafilterM; str="F:"+pips.madiff.FS+":M:"+pips.madiff.MS+":S:"+pips.madiff.FS+":FM:"+pips.MinMax;
			Log("GetMarketCondition:iMA:F="+mafilterF+",M="+mafilterM+",S="+mafilterS+":a="+Ask+",b="+Bid);
		} else {
			pips.MinMax = pips.madiff.FM;
			pMid = mafilterS; str="F:"+pips.madiff.FS+":F:"+pips.madiff.MS+":M:"+pips.madiff.FM+":FM:"+pips.MinMax;
			Log("GetMarketCondition:iMA:F="+mafilterF+",S="+mafilterS+",M="+mafilterM+":a="+Ask+",b="+Bid);
		}
	}
	Log("GetMarketCondition:nMA:f="+normF+",m="+normM+",s="+normS+
		":dFM="+pips.madiff.FM+",dMS="+pips.madiff.MS+",dFS="+pips.madiff.FS+",dFF="+pips.madiff.FF+
		":pBM="+Pips.BuyTrend.Margin+",pSM="+Pips.SellTrend.Margin);
//	if(mafilterM > mafilterS ) {
//		if( mafilterF > mafilterM ) {
//			pips.madiff.FM = (mafilterF - mafilterM) / vPoint;
//			pips.madiff.MS = (mafilterM - mafilterS) / vPoint;
	if( normM > normS && pips.madiff.MS >= Pips.BuyTrend.Margin ) {
		if( normF > normM && pips.madiff.FM >= Pips.BuyTrend.Margin ) {
			if( pips.madiff.MS > pips.madiff.FM*3 )
				mktCond = UPTREND_RETRACEMENT;
			else {
				if( R<=pR && S<=pS ) {
					mktCond = UPTREND_RETRACEMENT;
				} else {
					pips.pdiff = ((Ask-mafilterF)/ vPoint) * 2;
					if( pips.pdiff > pips.madiff.FM )
						mktCond = UPTREND;
					else
						mktCond = UPTREND_RETRACEMENT;
				}
			}
		} else
		if( pMin==mafilterS && pMax - pMin > (pMax-pMid)*3 )
			mktCond = UPTREND_RETRACEMENT;
		else
		if( normF < normS && pips.madiff.FS >= Pips.BuyTrend.Margin ) {
			// GbpUsd #44,#45 2013.06.24 2013.07.01
			if( normS < normM && pips.madiff.MS >= Pips.BuyTrend.Margin )
				mktCond = DNTREND_RETRACEMENT;
			else
			if( mafilterFF < mafilterF )
				mktCond = UPTREND_REVERSAL;
			else
				mktCond = UPRANGE;
		} else {
//			if( mafilterS > mafilterF )
			if( normS > normF && pips.madiff.FS >= Pips.BuyTrend.Margin )
				mktCond = UPTREND_REVERSAL;	// failed GbpUsd #44,#45 2013.06.24 2013.07.01
			else {
				mktCond = RANGE; // UPTREND_RETRACEMENT;
				if( R<=pR && S<=pS )
					mktCond = DNRANGE;
				Log("GetMartCondition:RANGE1="+mktCond);
			}
		}
	} else
//		if( mafilterM < mafilterS ) {
//			if( mafilterF < mafilterM ) {
		if( normM < normS && pips.madiff.MS >= Pips.SellTrend.Margin ) {
			if( normF < normM && pips.madiff.FM >= Pips.SellTrend.Margin ) {
				if( pips.madiff.MS > pips.madiff.FM*3 )
					mktCond = DNTREND_RETRACEMENT;
				else
				if( R>=pR && S>=pS ) {
					mktCond = DNTREND_RETRACEMENT;
				} else {
					pips.pdiff = ((mafilterF - Bid) / vPoint) * 2;
					if( pips.pdiff > pips.madiff.FM )
						mktCond = DNTREND;
					else
						mktCond = DNTREND_RETRACEMENT;
				}
			} else
			if( pMax==mafilterS && pMax - pMin > (pMax-pMid)*3 )
				mktCond = DNTREND_RETRACEMENT;
			else
			if( normF > normS && pips.madiff.FS >= Pips.SellTrend.Margin ) {
				// GbpUsd #44,#45 2013.06.24 2013.07.01
				if( normS > normM && pips.madiff.MS >= Pips.SellTrend.Margin )
					mktCond = DNTREND_RETRACEMENT;
				else
				if( mafilterFF > mafilterF )
					mktCond = DNTREND_REVERSAL;
				else
					mktCond = DNRANGE;
			} else {
//				if( mafilterS > mafilterF )
				if( normS > normF && pips.madiff.FS >= Pips.SellTrend.Margin )
					mktCond = DNTREND_REVERSAL;	// failed GbpUsd #44,#45 2013.06.24 2013.07.01
				else {
					mktCond = RANGE; // DNTREND_RETRACEMENT;
					if( R>=pR && S>=pS )
						mktCond = UPRANGE;
					Log("GetMartCondition:RANGE2="+mktCond);
				}
			}
		} else {
//			if( mafilterM > mafilterF && mafilterF > mafilterFF && R<=pR && S<=pS )
			if( mafilterM > mafilterF && mafilterF > mafilterFF && pips.madiff.FM > Pips.SellTrend.Margin )
				mktCond = DNRANGE;
			else
//			if( mafilterM < mafilterF && mafilterF < mafilterFF && R>=pR && S>=pS )
			if( mafilterM < mafilterF && mafilterF < mafilterFF && pips.madiff.FM > Pips.BuyTrend.Margin )
				mktCond = UPRANGE;
			else
			if( pips.madiff.FM >= Pips.BuyTrend.Margin*3 && R>=pR && S>=pS )
				mktCond = UPRANGE;
			else
			if( pips.madiff.FM >= Pips.SellTrend.Margin*3 && R<=pR && S<=pS )
				mktCond = DNRANGE;
			Log("GetMartCondition:RANGE3="+mktCond);
		}
	comment(mktCond,str,pips.MinMax);
	Log("GetMarketCondition="+mktCond+" (UP="+UPTREND+",uRev="+UPTREND_REVERSAL+",uRtr="+UPTREND_RETRACEMENT+
		",uRnge="+UPRANGE+",rnge="+RANGE+",dRnge="+DNRANGE+
		",DN="+DNTREND+",dRev="+DNTREND_REVERSAL+",dRtr="+DNTREND_RETRACEMENT+")"+
		",pD="+pips.pdiff+",pFM="+pips.madiff.FM);
	return(mktCond);
}

void GetTradeMode(int mktCond, bool buyCond, bool sellCond, double R, double S) {
	BuyMode=-1; SellMode=-1;
	
	if( mktCond<0 )	{ // No MA filter
		if( buyCond )
			BuyMode = OP_BUY;
		else
			SellMode = OP_SELL;
		return;
	}
	
	if( buyCond ) {
		if( mktCond==RANGE || mktCond==DNRANGE ) {
			if( Ask < pMin )
				BuyMode = OP_BUY;
			else
				BuyMode = OP_BUYLIMIT;
		} else
		if( mktCond==UPRANGE ) {
			if( Ask<R && (R-S)/vPoint > Pips.BuyTrend.Margin && 
				(Ask-S)/vPoint > ((R-Ask)/vPoint)*3 )
				BuyMode = OP_BUYLIMIT;
			else
				BuyMode = OP_BUY;
		} else
		if( mktCond==DNTREND_RETRACEMENT ) {
			Log("ERRCOND:Skipped BUY cond for "+mktCond);
		} else
		if( mktCond==UPTREND ) {
			if( pips.madiff.FF > (Ask-mafilterFF)/vPoint)
				BuyMode = OP_BUY;
			else
				BuyMode = OP_BUYLIMIT;
		} else
			if( mktCond==DNTREND ||
				mktCond==UPTREND_RETRACEMENT ||
				mktCond==UPTREND_REVERSAL )
				BuyMode = OP_BUYLIMIT;
			else
				if( mktCond==DNTREND_REVERSAL ) {
					if( Ask<mafilterS && Ask<mafilterM && Ask<mafilterF )
						BuyMode = OP_BUY;
					else
						BuyMode = OP_BUYLIMIT;
				} else
					Log("ERRCOND:Missing BUY cond for "+mktCond);
	} else
	if( sellCond ) {
		if( mktCond==RANGE || mktCond==UPRANGE ) {
			if( Bid > pMax )
				SellMode = OP_SELL;
			else
				SellMode = OP_SELLLIMIT;
		} else
		if( mktCond==DNRANGE ) {
			if( Bid>S && (R-S)/vPoint > Pips.SellTrend.Margin && 
				(R-Bid)/vPoint > ((Bid-S)/vPoint)*3 )
				SellMode = OP_SELLLIMIT;
			else
				SellMode = OP_SELL;
		} else
		if( mktCond==UPTREND_RETRACEMENT ) {
			Log("ERRCOND:Skipped SELL cond for "+mktCond);
		} else
		if( mktCond==DNTREND ) {
			if( pips.madiff.FF > (mafilterFF-Bid)/vPoint)
				SellMode = OP_SELL;
			else
				SellMode = OP_SELLLIMIT;
		} else
			if( mktCond==UPTREND ||
				mktCond==DNTREND_RETRACEMENT ||
				mktCond==DNTREND_REVERSAL )
				SellMode = OP_SELLLIMIT;
			else
			if( mktCond==UPTREND_REVERSAL ) {
				if( Bid>mafilterS && Bid>mafilterM && Bid>mafilterF )
					SellMode = OP_SELL;
				else
					SellMode = OP_SELLLIMIT;
			} else
				Log("ERRCOND:Missing SELL cond for "+mktCond);
	}
	Log("GetTradeMode:mC="+mktCond+",bC="+buyCond+",sC="+sellCond+",bm="+BuyMode+",sm="+SellMode+
		" (ob="+OP_BUY+",os="+OP_SELL+",bl="+OP_BUYLIMIT+",sl="+OP_SELLLIMIT+",bs="+OP_BUYSTOP+",ss="+OP_SELLSTOP+")");
}

double GetEntryPrice(int mktCond, int dir, double R, double pR, double S, double pS) {
	double ePrice=-1, sr2ma, qMax,qMin;
	
	if( dir == OP_BUY )
		ePrice = Ask;
	else
	if( dir == OP_SELL )
		ePrice = Bid;
	else
	if( dir == OP_BUYLIMIT ) {
		if( mktCond==RANGE ) {
			if( Ask<pMax )
				ePrice = pMin;
			else
				ePrice = (pMin+pMax)/2;
		} else
		if( mktCond==UPRANGE )
			ePrice = S + (Pips.BuyTrend.Margin * vPoint);
		else
		if( mktCond==UPTREND )
			ePrice = mafilterFF;
		else
		if( mktCond==DNTREND ) {
//			sr2ma = (mafilterF - S);
//			ePrice = S - sr2ma;
			sr2ma = (mafilterF - Ask);
			ePrice = Ask - sr2ma;
			if( ePrice > S || (S-ePrice)/vPoint < Pips.BuyTrend.Margin )
				ePrice = S - sr2ma;
		} else
		if( mktCond==UPTREND_RETRACEMENT || mktCond==UPTREND_REVERSAL || mktCond==DNTREND_REVERSAL ) {
			if( Ask > S ) {
				ePrice = S;
				if( pS<S )
					ePrice = pS;
			} else
			if( Ask > pMin )	// ask below support
				ePrice = pMin;
			else
				Log("GetEntryPrice:ERRCOND=OutOfRange:dir="+dir);
		}
	} else
	if( dir == OP_SELLLIMIT ) {
		if( mktCond==RANGE ) {
			if( Bid<pMax )
				ePrice = pMax;
			else
				ePrice = (pMin+pMax)/2;
		} else
		if( mktCond==DNRANGE )
			ePrice = R - (Pips.SellTrend.Margin * vPoint);
		else
		if( mktCond==DNTREND )
			ePrice = mafilterFF;
		else
		if( mktCond==UPTREND ) {
//			sr2ma = (R - mafilterF);
//			ePrice = R + sr2ma;
			sr2ma = (Bid - mafilterF);
			ePrice = Bid + sr2ma;
			if( ePrice < R || (R-ePrice)/vPoint < Pips.SellTrend.Margin )
				ePrice = R + sr2ma;
		} else
		if( mktCond==DNTREND_RETRACEMENT || mktCond==DNTREND_REVERSAL || mktCond==UPTREND_REVERSAL ) {
			if( Bid < R ) {
				ePrice = R;
				if( pR>R )
					ePrice = pR;
			} else
			if( Bid<pMax )
				ePrice = pMax;
			else
				Log("GetEntryPrice:ERRCOND=OutOfRange:dir="+dir);
		}
	}
	ePrice= NormalizeDouble(ePrice,Digits);
	Log("GetEntryPrice:dir="+dir+",mC="+mktCond+",r="+R+",s="+S+",ma="+sr2ma+",a="+Ask+",b="+Bid+":p="+ePrice);
	return(ePrice);
}

double GetExitPrice(int mktCond, int dir, double entryPrice, double R, double pR, double S, double pS) {
	double xPrice=-1;
	int pips.distance=-1;
	
	if( dir == OP_BUY ) {
		if( mktCond==RANGE ) {
			if( Ask > S )
				xPrice = S - (Pips.BuyTrend.Margin * vPoint);
			else
				xPrice = GetStopLoss(dir,R,pR,S,pS);
		} else
		if( mktCond==UPRANGE ) {
			if( (xPrice-S)/vPoint < Pips.BuyTrend.Margin && xPrice > pMax)
				xPrice = S - (Pips.BuyTrend.Margin * vPoint);
			else
				xPrice = S;
		} else
		if( mktCond==UPTREND )
			if( pips.madiff.FM > Pips.BuyTrend.Margin * 2 )
//				if( S<mafilterFF )
//					xPrice = S;
//				else
					xPrice = mafilterF;
			else
				xPrice = (mafilterM+mafilterS)/2;
		else
		if( mktCond==DNTREND_REVERSAL ) {
			pips.distance = NormalizeDouble((pMax-pMin)/vPoint,0);
			xPrice = Ask - (pips.distance*vPoint);
		} else {
			xPrice = mafilterM;
			pips.distance = (Ask - xPrice) / vPoint;
			if( pips.distance > Pips.Max )
				xPrice = mafilterF;
		}
	} else
	if( dir == OP_SELL ) {
		if( mktCond==RANGE ) {
			if( Bid < R )
				xPrice = R + (Pips.SellTrend.Margin * vPoint);
			else
				xPrice = GetStopLoss(dir,R,pR,S,pS);
		} else
		if( mktCond==DNRANGE ) {
			if( (R-xPrice)/vPoint < Pips.SellTrend.Margin && xPrice < pMax)
				xPrice = R + (Pips.SellTrend.Margin * vPoint);
			else
				xPrice = R;
		} else
		if( mktCond==DNTREND )
			if( (normM-normF)/vPoint > Pips.SellTrend.Margin * 2 )
//				if( R>mafilterFF )
//					xPrice = R;
//				else
					xPrice = mafilterF;
			else
				xPrice = (mafilterM+mafilterS)/2;
		else
		if( mktCond==UPTREND_REVERSAL ) {
			pips.distance = NormalizeDouble((pMax-pMin)/vPoint,0);
			xPrice = Bid + (pips.distance*vPoint);
		} else {
			xPrice = (mafilterM+mafilterS) / 2;
			pips.distance = (xPrice - Bid) / vPoint;
			if( pips.distance > Pips.Max )
				xPrice = mafilterF;
		}
	} else
	if( dir == OP_BUYLIMIT ) {
		if( mktCond==RANGE ) {
			pips.distance = (Ask - entryPrice) / vPoint;
			xPrice = entryPrice - (pips.distance*vPoint);
		} else
		if( mktCond==DNRANGE ) {
			if( S<entryPrice )
				xPrice = S - (Pips.BuyTrend.Margin * vPoint);
			else
				if( pMax<entryPrice )
					xPrice = pMax;
				else
					Log("ERRCOND:exitPrice:mC="+mktCond+":bm="+dir);
		} else
		if( mktCond==UPTREND )
			xPrice = mafilterF;
		else
		if( mktCond==DNTREND ) {
//			pips.distance = ((R - entryPrice) / vPoint) / StopPC.BuyLimit;		// X% of range
//			xPrice = NormalizeDouble(entryPrice - (pips.distance * vPoint), Digits);
			pips.distance = (Ask - entryPrice) / vPoint;
			xPrice = entryPrice - (pips.distance*vPoint);
		} else
		if( mktCond==UPTREND_REVERSAL ) {	// GbpUsd #36 2013.05.16
			if( pR < R )
				xPrice = pR;
			else
				xPrice = entryPrice - (Ask-entryPrice)/2;
		} else
		if( mktCond==UPTREND_RETRACEMENT || mktCond==DNTREND_REVERSAL ) {
			if( entryPrice > normM )	// GbpUsd #7
				xPrice = normM;
			else
			if( Pips.BuyTrend.Margin > Pips.Min )
				xPrice = entryPrice - (Pips.BuyTrend.Margin*vPoint);
			else {
				Log("GetExitPrice:OutOfRange:dir="+dir);
				xPrice = entryPrice - (15*vPoint);
			}
		} else
			Log("GetExitPrice:ERRCOND="+mktCond);
	} else
	if( dir == OP_SELLLIMIT ) {
		if( mktCond==RANGE ) {
			pips.distance = (entryPrice - Bid) / vPoint;
			xPrice = entryPrice + (pips.distance*vPoint);
		} else
		if( mktCond==DNRANGE ) {
			if( R>entryPrice )
				xPrice = R + (Pips.SellTrend.Margin * vPoint);
			else
				if( pMax>entryPrice )
					xPrice = pMax;
				else
					Log("ERRCOND:exitPrice:mC="+mktCond+":bm="+dir);
		} else
		if( mktCond==DNTREND )
			xPrice = mafilterF;
		else
		if( mktCond==UPTREND ) {
//			pips.distance = ((entryPrice - R) / vPoint) / StopPC.SellLimit;	// X% of range
//			xPrice = NormalizeDouble(entryPrice + (pips.distance * vPoint), Digits);
			pips.distance = (entryPrice - Bid) / vPoint;
			xPrice = entryPrice + (pips.distance*vPoint);
		} else
		if( mktCond==UPTREND_REVERSAL ) {	// GbpUsd #36 2013.05.16
			if( pS > S )
				xPrice = pS;
			else
				xPrice = entryPrice + (entryPrice-Bid)/2;
		} else
		if( mktCond==DNTREND_RETRACEMENT || mktCond==UPTREND_REVERSAL ) {
			if( entryPrice < normM )	// GbpUsd #7
				xPrice = normM;
			else
			if( Pips.SellTrend.Margin > Pips.Min )
				xPrice = entryPrice + (Pips.SellTrend.Margin*vPoint);
			else {
				Log("GetExitPrice:OutOfRange:dir="+dir);
				xPrice = entryPrice + (15*vPoint);
			}
		}
	}
	Log("GetExitPrice:dir="+dir+",mC="+mktCond+":d="+pips.distance+",p="+xPrice);
	if(	((dir==OP_BUY || dir==OP_BUYLIMIT || dir==OP_BUYSTOP) && xPrice >= entryPrice) ||
		((dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_SELLSTOP) && xPrice <= entryPrice) ) {
		Log("ERRCOND:exitPrice");
		xPrice=-1;
	}
	return(xPrice);
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
	bool scanH=false, scanL=false;
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
		if( ((oMC==UPTREND || oMC==UPTREND_RETRACEMENT || oMC==UPRANGE) && oType==OP_BUY) ||
			((oMC==DNTREND || oMC==DNTREND_RETRACEMENT || oMC==DNRANGE) && oType==OP_SELL) ) {
			// Trend playing mode
			int pips.distance;
	
			if( oType==OP_BUY )
				pips.distance = (Bid-ooPrice)/vPoint;
			else
				pips.distance = (ooPrice-Ask)/vPoint;
				
			Log("AdjustStop5:"+Counter+":oTic="+oTicket+",oMC="+oMC+",oType="+oType+",pD="+pips.distance+
					":bAj="+Pips.BuyAdjust.Start+",sAj="+Pips.SellAdjust.Start);
			
			if( oType==OP_BUY  && pips.distance < Pips.BuyAdjust.Start ||
				oType==OP_SELL && pips.distance < Pips.SellAdjust.Start ) {
				Log("AdjustStop6:Abort oTic="+oTicket);
				continue;
			}

			if( oType==OP_SELL && !scanH ) {
				sSL = GetHighestR(R);
				scanH=true;
			} else
			if( oType==OP_BUY && !scanL ) {
				bSL = GetLowestS(S);
				scanL=true;
			}
			
			Log("AdjustStop7:oTic="+oTicket+",ooP="+ooPrice+",oSL="+oSL+",nSL="+bSL+","+sSL);
			if( oType==OP_SELL && (sSL<0 || sSL>oSL) ||
				oType==OP_BUY  && (bSL<0 || bSL<oSL) )
				continue;
		} else {
			// Counter trend mode
			if( oType==OP_BUY && S > oSL )
				bSL = S;
			else
			if( oType==OP_SELL && R < oSL )
				sSL = R;
			else {
				Log("AdjustStop4:Abort oTic="+oTicket+",oMC="+oMC+",oT="+oType+",oSL="+bSL+","+sSL+",R="+R+",S="+S);
				continue;
			}
			scanH=false; scanL=false;
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

