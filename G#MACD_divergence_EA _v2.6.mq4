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
//|		v2.5	Parameterize options from booleans to int for backtesting configuration
//|		v2.6	Establish market condition based on MAs
//|				Convert Print() to Log()
//|             Introduced Pips.Match
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

#define VER "2.6"

// Structure #2 (Optional): Input parameters

extern string EAName = "EA8033";
extern double MagicNumber = 8033;
extern int TimeFrame = 240;

//extern bool MM = TRUE;
extern double RiskRatio = 2;
extern int stopType = 0;			// 0=stopBarCount, 1=SR level
extern int NoClose = 0;				// 0=false, 1=true
extern int ForceOppositeClose = 0;	// 0=false, 1=true
extern int OppositeClose = 0;		// 0=false, 1=true
extern int AdjustStop = true;		// 0=false, 1=true
extern int ConcurrentOrders = 0;	// 0=no limit

extern int Pips.Min = 10;
extern int Pips.Max = 200;
extern int Pips.Match = 0;			// 0 = no check
extern int Pips.BS_Tol = 0;
extern int Pips.SS_Tol = 0;
extern int Pips.BUY_Tol = 0;		// 0=no extra pips
extern int Pips.SELL_Tol = 0;
extern int Pips.MA_BUY_distance  = 100;	// in pips
extern int Pips.MA_SELL_distance = 100;	// in pips

extern double LotDigits =2;
extern int TakeProfit = 0;
extern int PartialClosePortion = 0;
extern int StopLossBarCount = 1;
extern int StopLossTolerancePc = 0;

extern double TrailingStart = 0;
extern double TrailingStop  = 0;
extern double TrailingStep  = 0;

extern int  Slippage = 5;
extern bool LogToFile = false;
extern bool EnterOpenBar = true;
extern bool Show.Comments = true;
extern bool GapCheck = true;
//---- MA Filter input parameters
extern string separator1 = "*** MA Filter Settings ***";
extern int MAFilter = 1;		// 0=false, 1=true
//extern bool MAFilterRev = false;
//extern int MATime = 0;
//extern int MAPeriod = 50;
//extern int MAMethod=1;
//extern int MAShift=1;

extern int FastMATime = 0;
extern int FastMAPeriod = 34;
extern int FastMAType = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int FastMAPrice = 0;
extern int FastMAShift = 0;
//---------------------
extern int MidMATime = 0;
extern int MidMAPeriod = 89;
extern int MidMAType = 1; //0:SMA 1:EMA 2:SMMA 3:LWMA
extern int MidMAPrice = 0;
extern int MidMAShift = 0;
//---------------------
extern int SlowMATime = 0;
extern int SlowMAPeriod = 200;
extern int SlowMAType = 0; //0:SMA 1:EMA 2:SMMA 3:LWMA
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
int BuyMode=OP_BUY, SellMode=OP_SELL;
int Counter, vSlippage;
double ticket, number, vPoint, RValue;
double mafilterF,mafilterM,mafilterS;
bool NewLine=true;
// Structural #3 (Optional): expert initialization function

int init() {
	if(Digits==3 || Digits==5) {
		vPoint=Point*10; vSlippage=Slippage*10;
	}
	else {
		vPoint=Point; vSlippage=Slippage;
	}
	Log("init:vP="+vPoint+":"+OP_BUY+","+OP_SELL+","+OP_BUYLIMIT+","+OP_SELLLIMIT+","+OP_BUYSTOP+","+OP_SELLSTOP);
	if( IsTesting() && !IsVisualMode()){
		Show.Comments   = false;
//		Show.Objects    = false;
		GapCheck        = false;
	}
	if(LogToFile){startFile();}
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

	if( TrailingStop>0 && TrailingStart > 0 )
		TrailOrder (TrailingStart, TrailingStop);

	bool OpenBar=true;
	if(EnterOpenBar)
		if(iVolume(NULL,0,0)>1)
			OpenBar=false;

	if(!OpenBar)
		return(0);

//----------------------------------------------------
// Section 3B: Indicator Calling


	bool CloseBuy=false, CloseSell=false, OpenBuy=false, OpenSell=false;
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

	if( !BuyCondition && !SellCondition )
		return(0);

//------------------------------------------------
// Section 3C: Entry Conditions

	LogSeparator1();

//	if(MAFilter || MAFilterRev) {
//		double mafilter=iMA(NULL,MATime,MAPeriod,0,MAMethod,PRICE_CLOSE,MAShift);
	GetModeByFilterFMS();
	
	double  R = iCustom(NULL,0,"Support and Resistance (Barry)",0,0);
	double  S = iCustom(NULL,0,"Support and Resistance (Barry)",1,0);
	double pR = GetPrevR(R);
	double pS = GetPrevS(S);
//	Log("Barry:"+i+","+j+":R="+R+",S="+S+",pR="+pR+",pS="+pS);
	Log("Barry:R="+R+",S="+S+",pR="+pR+",pS="+pS);

	double LotSize = 0, TradeSL, TradeTP, pEntry,pExit;
	int pips=0;
	bool pipsOk=true;

	if( BuyCondition ) {
//			(MAFilter==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) &&
//			(MAFilterRev==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) ) {
//			(MAFilter==false || (MAFilter && Ask>mafilter)) &&
//			(MAFilterRev==false || (MAFilter && Ask<mafilter)) ) {
		if( stopType==0 )
			TradeSL = GetStopLoss(BuyMode);
		else
//		if( stopType==1 )
			TradeSL = S - (Pips.BUY_Tol * vPoint);

		if( BuyMode==OP_BUY ) {
			pEntry = Ask;
			pExit = TradeSL;
		} else {
			if( BuyMode==OP_BUYLIMIT )
				pEntry = TradeSL;
			else
				pEntry = R + (Pips.BS_Tol * vPoint);
			pExit  = getStopLossBySR(BuyMode,pEntry,S,pS,R,pR);
		}

		if( pExit>0 && !MatchLastOrderPrice(pEntry) ) {
			pips = GetPips(BuyMode,pEntry,pExit);
			if( BuyMode==OP_BUY )
				pExit = pEntry - (pips*vPoint);
			if( Pips.Max > 0 && pips > Pips.Max ) {
				Log("Pips.Max="+Pips.Max+"<"+pips);
				pipsOk=false;
			} else
				if(	Pips.Min > 0 && pips < Pips.Min )
					pipsOk=false;
			if(	pipsOk ) {
				OpenBuy = true;
				if( OppositeClose>0 )
					CloseSell = true;
			} else {
				OpenBuy = false;
				if( ForceOppositeClose>0 )
					if( OppositeClose>0 )
						CloseBuy=true;
			}
		}
	} else
		if( SellCondition ) {
//				(MAFilter==false || (MAFilter && (mafilterF<mafilterM && mafilterM<mafilterS))) &&
//				(MAFilterRev==false || (MAFilter && (mafilterF>mafilterM && mafilterM>mafilterS))) ) {
//				(MAFilter==false || (MAFilter && Bid<mafilter)) &&
//				(MAFilterRev==false || (MAFilter && Bid>mafilter)) ) {
			if( stopType==0 )
				TradeSL = GetStopLoss(SellMode);
			else
//			if( stopType==1 )
				TradeSL = R + (Pips.SELL_Tol * vPoint);

			if( SellMode==OP_SELL ) {
				pEntry = Bid;
				pExit = TradeSL;
			}
			else {
				if( SellMode==OP_SELLLIMIT )
					pEntry = TradeSL;
				else
					pEntry = S - (Pips.SS_Tol * vPoint);
				pExit  = getStopLossBySR(SellMode,pEntry,S,pS,R,pR);
			}

			if( pExit>0 && !MatchLastOrderPrice(pEntry) ) {
				pips = GetPips(SellMode,pEntry,pExit);
				if( SellMode==OP_SELL )
					pExit = pEntry + (pips*vPoint);
				if( Pips.Max > 0 && pips > Pips.Max ) {
					Log("Pips.Max="+Pips.Max+"<"+pips);
					pipsOk=false;
				} else
					if(	Pips.Min > 0 && pips < Pips.Min )
						pipsOk=false;
				if(	pipsOk ) {
					OpenSell = true;
					if( OppositeClose>0 )
						CloseBuy=true;
				} else {
					OpenSell = false;
					if( ForceOppositeClose>0 )
						if( OppositeClose>0 )
							CloseBuy=true;
				}
			}
		}

	Log("R="+R+",S="+S+",SL="+TradeSL+","+pExit+",P="+pips);
	Log("EntryCond:bc="+BuyCondition+",sc="+SellCondition+
		",ob="+OpenBuy+",cs="+CloseSell+",os="+OpenSell+",cb="+CloseBuy);
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

	if(!OpenBuy && !OpenSell)
		return(0);
//--------------------------------------------------
// Section 3E: Order Placement
//	Buy at Ask, Sell at Bid

	int expiration=CurTime()+PERIOD_D1*60;

	while(true) {
		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenBuy==true) {
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
			while(ticket<=0 && number<20) {
				number = number+1;
				RefreshRates();
				if( BuyMode==OP_BUY ) {
					ticket = OrderSend(Symbol(),OP_BUY,LotSize,
								Ask,vSlippage,pExit,TradeTP,EAName, MagicNumber, 0, Green);
				} else
//				if( BuyMode==OP_BUYLIMIT )
//					ticket = OrderSend(Symbol(),OP_BUYLIMIT,LotSize,
//								pEntry,0,pExit,TradeTP,EAName, MagicNumber, expiration, Green);
//				else
//				if( BuyMode==OP_BUYSTOP )
//					ticket = OrderSend(Symbol(),OP_BUYSTOP,LotSize,
					ticket = OrderSend(Symbol(),BuyMode,LotSize,
								pEntry,0,pExit,TradeTP,EAName, MagicNumber, expiration, Green);

				if(ticket<=0) {
					int error=GetLastError();
					int mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
					pips = NormalizeDouble((Ask-pExit)/vPoint,0);
					Log("ERR:OrderSend:"+number+","+error+",oT="+BuyMode+
						",Ask="+Ask+",sl="+pExit+",p="+pips+",mktP="+mktPips);
					if( error==130 ||
						error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
						break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
					}
					//---- 10 seconds wait
					Sleep(10000);
				}
//				return (ticket);
			}
		}

		if ((ConcurrentOrders==0 || OrdersTotalMagicOpen()<=ConcurrentOrders) && OpenSell==true) {
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
			while(ticket<=0 && number<20) {
				number = number+1;
				RefreshRates();
				if( SellMode==OP_SELL ) {
					ticket= OrderSend(Symbol(),OP_SELL, LotSize,
									Bid,vSlippage,pExit,TradeTP, EAName, MagicNumber, 0, Red);
				} else
//				if( SellMode==OP_SELLLIMIT )
//					ticket= OrderSend(Symbol(),OP_SELLLIMIT, LotSize,
//									pEntry,0,pExit,TradeTP, EAName, MagicNumber, expiration, Red);
//				else
//				if( SellMode==OP_SELLSTOP )
//					ticket= OrderSend(Symbol(),OP_SELLSTOP, LotSize,
					ticket= OrderSend(Symbol(),SellMode, LotSize,
									pEntry,0,pExit,TradeTP, EAName, MagicNumber, expiration, Red);

				if(	ticket<=0 ) {
					error=GetLastError();
					mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
					pips = NormalizeDouble((pExit-Bid)/vPoint,0);
					Log("ERR:OrderSend:"+number+","+error+",oT="+SellMode+
						",Bid="+Bid+",sl="+pExit+",p="+pips+",mktP="+mktPips);
					if( error==130 ||
						error==4107 ) {	// 129 (ERR_INVALID_PRICE), 130 (ERR_INVALID_STOPS)
						break;			// 138 (ERR_REQUOTE), 4107 (ERR_INVALID_TP)
					}
					//---- 10 seconds wait
					Sleep(10000);
				}
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

int GetPips(int dir, double entryPrice, double exitPrice)
{
	double slPips,tolPips;
	if( dir==OP_BUY || dir==OP_BUYLIMIT || dir==OP_BUYSTOP )
		slPips=(entryPrice - exitPrice) / vPoint;
	else
	if( dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_SELLSTOP )
		slPips=(exitPrice - entryPrice) / vPoint;

	if( dir==OP_BUY && Pips.BUY_Tol>0 ) {
		tolPips = Pips.BUY_Tol;
		slPips = slPips + tolPips;
	}
	if( dir==OP_SELL && Pips.SELL_Tol>0 ) {
		tolPips = Pips.SELL_Tol;
		slPips = slPips + tolPips;
	}
/*
	int mktPips = MarketInfo(Symbol(), MODE_STOPLEVEL) + MarketInfo(Symbol(), MODE_SPREAD);
//	Log("GetPips:eP="+entryPrice+",eP="+exitPrice+":mktP="+mktPips+",P="+slPips+
//			",tolP="+tolPips+",srT="+Pips.BUY_Tol+",slP="+slPips - Pips.BUY_Tol);
	if(slPips < mktPips) {
		int diff = mktPips - slPips;
		Log("GetPips:mP="+mktPips+",slP="+slPips+",tol="+tolPips+",dif="+diff);
		if( diff <= tolPips )
			slPips = mktPips+1;
		else
			return(-1);
	}
*/
	Log("GetPips:eP="+entryPrice+",eP="+exitPrice+":minP="+Pips.Min+",P="+slPips+
			",tolP="+tolPips+",srT="+Pips.BUY_Tol+",slP="+(slPips - tolPips));
	if(slPips < Pips.Min)
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
		if(	(Pips.Min > 0 && pips < Pips.Min) ||
			(Pips.Max > 0 && pips > Pips.Max) )
			return(-1);

		double usdsgdRate = NormalizeDouble(iClose("USDSGD",PERIOD_D1,1),LotDigits);
		double cashAtRisk = NormalizeDouble(AccountFreeMargin() * RiskRatio/100, LotDigits);

		RValue = pips * usdsgdRate;
		double stopCost = RValue * 10;

		lots = NormalizeDouble(cashAtRisk / stopCost, LotDigits);
		Log("MM:"+ NormalizeDouble(AccountFreeMargin(),LotDigits)+":Pips="+pips+">"+Pips.Min+
			":UsdSgd="+usdsgdRate+",CshRisk="+cashAtRisk+",Rval="+RValue+",Lots="+lots);
		Comment("MM:", NormalizeDouble(AccountFreeMargin(),LotDigits),":Pips=",pips,">",Pips.Min,
			":UsdSgd=",usdsgdRate,",CshRisk=",cashAtRisk,",Rval=",RValue,",Lots=",lots);

//		lots = NormalizeDouble(AccountFreeMargin() * RiskRatio/100 / 1000.0, LotDigits);
//		if(lots < minlot) lots = minlot;
		if(lots < minlot)
		{
			Log("Insufficient fund:"+ lots+ " + minlot="+ minlot);
			lots = -1;
			return (lots);
		}
		if(lots > MaximalLots) lots = MaximalLots;
		if(AccountFreeMargin() < Ask * lots * lotsize / leverage) {
			Log("We have no money. Lots = "+ lots+ " + Free Margin = "+ AccountFreeMargin());
			lots = -1;
			return (lots);
		}
//	}
//	else
//		lots=NormalizeDouble(Lots,Digits);

	return(lots);
}

double GetStopLoss(int dir) {
	double stopLoss,stopLossTol;
	if( dir==OP_BUY || dir==OP_BUYLIMIT || dir==OP_SELLSTOP ) {
		stopLoss = Low[iLowest(Symbol(), 0, MODE_LOW, StopLossBarCount, 1)];
//		Log("GetStopLoss:"+stopLoss);
//		stopLoss = stopLoss - (stopLoss * StopLossTolerancePc/100);
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss - stopLossTol;
	} else {
//	if( dir==OP_SELL || dir==OP_SELLLIMIT || dir==OP_BUYSTOP ) {
		stopLoss = High[iHighest(Symbol(), 0, MODE_HIGH, StopLossBarCount, 1)];
//		Log("GetStopLoss:"+stopLoss);
//		stopLoss = stopLoss + (stopLoss * StopLossTolerancePc/100);
		stopLossTol = stopLoss * StopLossTolerancePc/100;
		stopLoss = stopLoss + stopLossTol;
	}
	Log("GetStopLoss:dir="+dir+"(0=B,1=S,2=BL,3=SL,4=BS,5=SS):"+stopLossTol+":"+Ask+":"+Bid+":"+stopLoss);
	return(stopLoss);
}

double getStopLossBySR(int dir, double entryPrice, double S1, double S2, double R1, double R2)
{
	double srSL=-1;
	int stopDistance;

	if( dir==OP_BUYLIMIT ) {
		if( entryPrice>S1 ) {
			stopDistance = (entryPrice - S1) / vPoint;
			if( stopDistance < Pips.Min )
				stopDistance = (entryPrice - S2) / vPoint;
		} else
			stopDistance = (entryPrice - S2) / vPoint;
		if( stopDistance > Pips.Min ) {
			srSL = entryPrice - ((stopDistance + vSlippage) * vPoint);
			if( srSL > mafilterS ) {
				if( srSL > mafilterF )
					srSL = mafilterF;
				else
				if( srSL > mafilterM )
					srSL = mafilterM;
				else
					srSL = mafilterS;
			}
		}
	} else
	if( dir==OP_SELLLIMIT ) {
		if( entryPrice<R1 ) {
			stopDistance = (R1 - entryPrice) / vPoint;
			if( stopDistance < Pips.Min )
				stopDistance = (R2 - entryPrice) / vPoint;
		} else
			stopDistance = (R2 - entryPrice) / vPoint;
		if( stopDistance > Pips.Min ) {
			srSL = entryPrice + ((stopDistance + vSlippage) * vPoint);
			if( srSL < mafilterS ) {
				if( srSL < mafilterF )
					srSL = mafilterF;
				else
				if( srSL < mafilterM )
					srSL = mafilterM;
				else
					srSL = mafilterS;
			}
		}
	} else
	if( dir==OP_BUYSTOP ) {
		if( entryPrice<R1 )
			entryPrice=R1;
		stopDistance = (entryPrice - S1) / vPoint;
		if( stopDistance > Pips.Min )
			srSL = entryPrice - ((stopDistance + vSlippage) * vPoint);
		
	} else
	if( dir==OP_SELLSTOP ) {
		if( entryPrice>S1 )
			entryPrice=S1;
		stopDistance = (entryPrice - R1) / vPoint;
		if( stopDistance > Pips.Min )
			srSL = entryPrice + ((stopDistance + vSlippage) * vPoint);
	}
	
	Log("getStopLossBySR:dir="+dir+",eP="+entryPrice+",sL="+srSL+",sD="+stopDistance);
	return(srSL);
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
void Log(string str)
{
//	str = "["+Day()+"-"+Month()+"-"+Year()+" "+Hour()+":"+Minute()+":"+Seconds()+"] "+str+"\n";
	if( NewLine)
		str = str+"\n";

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

void GetModeByFilterFMS() {
	if(	MAFilter<=0 )
		return;
		
	mafilterF=iMA(NULL,FastMATime,FastMAPeriod,0,FastMAType,PRICE_CLOSE,FastMAShift);
	mafilterM=iMA(NULL, MidMATime, MidMAPeriod,0, MidMAType,PRICE_CLOSE, MidMAShift);
	mafilterS=iMA(NULL,SlowMATime,SlowMAPeriod,0,SlowMAType,PRICE_CLOSE,SlowMAShift);

	int pips.MA_distance;
	double eP;
	
	if( mafilterF > mafilterM && mafilterM > mafilterS ) {
		// uptrend
		SellMode = OP_SELLSTOP;
		eP = Ask;
		pips.MA_distance = (eP-mafilterF)/vPoint;
		if( pips.MA_distance > Pips.MA_BUY_distance )
			BuyMode = OP_BUYLIMIT;
		else
			BuyMode = OP_BUY;
	} else
		if( mafilterF < mafilterM && mafilterM < mafilterS ) {
			// downtrend
			BuyMode = OP_BUYSTOP;
			eP = Bid;
			pips.MA_distance = (mafilterF-eP)/vPoint;
			if( pips.MA_distance > Pips.MA_SELL_distance )
				SellMode = OP_SELLLIMIT;
			else
				SellMode = OP_SELL;
		} else {
				// ranging market condition
				BuyMode = OP_BUYSTOP;
				SellMode = OP_SELLSTOP;
			}
	Log("MAFilter:f="+mafilterF+",m="+mafilterM+",s="+mafilterS+",BM="+BuyMode+",SM="+SellMode+
			" (ob="+OP_BUY+",os="+OP_SELL+",bl="+OP_BUYLIMIT+",sl="+OP_SELLLIMIT+",bs="+OP_BUYSTOP+",ss="+OP_SELLSTOP+")"+
			",eP="+eP+",maDist="+pips.MA_distance);
}

double GetPrevR(double val) {
	return(GetPrevSR(0,val));
}
double GetPrevS(double val) {
	return(GetPrevSR(1,val));
}
double GetPrevSR(int SR,double val) {
	int i=0;
	double pVal = val;
	while( pVal == val && i<15) {
		i=i+1;
		pVal = iCustom(NULL,0,"Support and Resistance (Barry)",SR,i);
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

void adjustStop(int dir, double R, double S)
{
	RefreshRates();
	int oTotal = OrdersTotal();
	if( oTotal<=0 )
		return;

	LogSeparator2(); NewLine=false;
	Log("adjustStop1:"+dir+"(0=B+1=S)+"+oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		int ticket=0,oType=OrderType();
		if( oType!=dir || oType>1 ) {
			Log("adjustStop2:Abort oTic="+oTicket+",oT="+oType+" (ob=0,os=1,bl=2,sl=3,bs=4,ss=5)");
			continue;
		}
		if( OrderProfit()<=0 ) {
			Log("adjustStop3:Abort oTic="+oTicket);
			continue;
		}
		if( OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber ) {
			Log("adjustStop4:Abort oTic="+oTicket);
			continue;
		}

		double SL,ooPrice = OrderOpenPrice(), oSL=OrderStopLoss();
//		if( (oType==OP_BUY && oSL < ooPrice) ||
//			(oType==OP_SELL && oSL > ooPrice) )
//			SL = ooPrice;	// Protect profits already gained
//		else
//			SL = GetStopLoss(oType);

		Log("adjustStop5:"+Counter+":oTic="+oTicket+",oType="+oType+",oProfit="+OrderProfit()+","+OrderMagicNumber());
/*
		int stopDistance;
		if( oType==OP_BUY ) {
			stopDistance = (S - oSL) / vPoint;
			Log("adjustStop6:oTic="+oTicket+",oSL="+oSL+",S="+S+",SD="+stopDistance+",nSL="+S-Pips.BUY_Tol*vPoint);
			if( S<oSL ||						// do not adjust if support below SL, or
				stopDistance < Pips.BUY_Tol )	// SL already close to support level
				continue;
			SL = S - (Pips.BUY_Tol*vPoint);
			if( SL<oSL )
				continue;
		} else
		if( oType==OP_SELL ) {
			stopDistance = (oSL - R) / vPoint;
			Log("adjustStop7:oTic="+oTicket+",oSL="+oSL+",R="+R+",SD="+stopDistance+",nSL="+R+Pips.BUY_Tol*vPoint);
			if( R>oSL ||						// do not adjust if resistance above SL, or
				stopDistance < Pips.BUY_Tol )	// SL already close to resistance level
				continue;
			SL = R + (Pips.BUY_Tol*vPoint);
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

		Log("adjustStop8:oTic="+oTicket+",ooP="+ooPrice+",R="+R+",S="+S+",oSL="+oSL+",nSL="+SL);

		if( SL!=ooPrice ) {
			if(	oType==OP_BUY )
				ooPrice = Ask;
			else
				ooPrice = Bid;
			if( GetPips(oType,ooPrice,SL) < 0 ) {
				Log("adjustStop9:Abort oTic="+oTicket);
				continue;
			}
		}
		RefreshRates();
		ticket = OrderModify(oTicket,ooPrice,SL,OrderTakeProfit(),0,Blue);
		Log("adjustStopModify:Dir="+dir+",oTic="+oTicket+",nTic="+ticket+
				",OOP="+ooPrice+",SL="+ SL+",Ask="+Ask+",Bid="+Bid+",bal="+AccountBalance());

		if( SL!=ooPrice && TakeProfit>0 && PartialClosePortion>0 ) {
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
	
	LogSeparator2(); NewLine=true;
}

void LogSeparator1() {
	Log("================================================================================================");
}
void LogSeparator2() {
	Log("------------------------------------------------------------------------------------------------");
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

	Log("close:"+type+"+"+oTotal);

	for(Counter=oTotal-1;Counter>=0;Counter--)
	{
		OrderSelect(Counter,SELECT_BY_POS,MODE_TRADES);
		int oTicket = OrderTicket();
		double oLots = OrderLots();
		int oType = OrderType();
		Log("close:"+Counter+":"+oTicket+","+OrderSymbol()+","+oType+","+OrderMagicNumber());
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

