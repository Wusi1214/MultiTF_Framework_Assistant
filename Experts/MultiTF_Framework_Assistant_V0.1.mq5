//+------------------------------------------------------------------+
//| MultiTF Framework Assistant（多周期趋势框架助手）                 |
//| 提醒优先的 MT5 多周期交易框架                                     |
//| 分析 H4/H1/M15/M5 多周期结构，给出入场、止损、止盈建议            |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1"
#property description "多周期交易框架EA（中文注释）：H4/H1/M15/M5信号，止损止盈，可选自动交易"

#include <Trade/Trade.mqh>

enum StrategyMode
{
   MODE_ALL = 0,                       // 全部策略
   MODE_TREND_PULLBACK = 1,            // 策略1：顺势回调
   MODE_BREAKOUT_CONTINUATION = 2,     // 策略2：突破延续
   MODE_REVERSAL_CONFIRMATION = 3      // 策略3：反转确认
};

enum TrendState
{
   TREND_UP = 1,
   TREND_DOWN = -1,
   TREND_RANGE = 0,
   TREND_TRANSITION = 2
};

enum TakeProfitMode
{
   TP_USE_TP1 = 1,      // 固定止盈：TP1
   TP_USE_TP2 = 2,      // 固定止盈：TP2
   TP_NO_FIXED = 3      // 不设固定止盈，只用保本/移动止盈
};

enum DailyLossMode
{
   DAILY_LOSS_PERCENT = 1,   // 按当日开始净值的百分比
   DAILY_LOSS_MONEY = 2      // 按固定金额（账户货币）
};

enum EquityProtectAnchorMode
{
   ANCHOR_INITIAL_DEPOSIT = 0,       // 始终锚定EA启动时的初始入金
   ANCHOR_ROLLING_AFTER_TRIGGER = 1, // 每次触发保护后按当时余额滚动更新
   ANCHOR_LAST_TRADE_OPEN = 2        // 以最近一次开仓时的余额为基准
};

input group "【一】策略模式与界面显示"
input StrategyMode InpMode = MODE_ALL;                 // 选择要运行的策略组合
input bool         InpEnableAutoTrade = true;          // 开启后，满足信号会自动开仓
input bool         InpUseAlerts = true;                // 出现信号时弹窗提醒
input bool         InpDrawLevels = true;               // 在图表画入场、止损、止盈线

input group "【二】仓位管理与交易过滤"
input bool         InpUseRiskPercent = true;           // true=按风险百分比算手数；false=用固定手数
input double       InpRiskPercent = 2.0;               // 单笔最大风险，占账户余额百分比
input double       InpFixedLots = 0.01;                // 固定手数，仅在关闭风险百分比时生效
input int          InpMaxOpenPositions = 1;            // 本 EA 同品种最多同时持仓数量
input double       InpMinRR = 1.5;                     // 最小盈亏比，低于该值不进场
input double       InpMaxSpreadPoints = 250;           // 最大允许点差，点差过大不进场
input double       InpMinSLPoints = 200;               // 最小止损距离，过近容易被噪音扫损
input double       InpMaxSLPoints = 5000;              // 最大止损距离，过远则放弃交易
input int          InpDeviationPoints = 30;            // 允许滑点，市价开仓时使用

input group "【三】多周期趋势识别"
input ENUM_TIMEFRAMES InpBigTrendTF = PERIOD_H4;       // 大方向周期，例如 H4
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;          // 趋势确认周期，例如 H1
input ENUM_TIMEFRAMES InpSetupTF = PERIOD_M15;         // 形态/位置周期，例如 M15
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M5;          // 入场触发周期，例如 M5
input int          InpFastEMA = 20;                    // 快速 EMA，用于判断短期方向
input int          InpSlowEMA = 60;                    // 慢速 EMA，用于判断趋势过滤
input int          InpRSIPeriod = 14;                  // RSI 周期，用于反转/背离判断
input int          InpLookbackBars = 120;              // 回看多少根 K 线寻找高低点结构

input group "【四】入场确认与止损缓冲"
input double       InpBreakoutBufferPoints = 80;       // 突破关键位后，额外确认的缓冲点数
input double       InpSLBufferPoints = 120;            // 止损放在结构外侧时，额外预留的缓冲点数
input double       InpReversalBreakBufferPoints = 120; // 策略3反转入场：突破小高/小低的额外确认点数
input bool         InpReversalRequireEMA60 = true;     // 策略3反转入场：是否要求收复/跌破慢速 EMA
input double       InpReversalBuyRsiMax = 45;          // 策略3做多：背离前 RSI 需低于该值，越小越严格
input double       InpReversalSellRsiMin = 55;         // 策略3做空：背离前 RSI 需高于该值，越大越严格

input group "【五】单笔利润保护：保本与移动止盈"
input bool         InpUseBreakEven = false;             // 启用保本止损
input double       InpBreakEvenStartPoints = 2000;      // 浮盈达到该点数后，把止损推到保本区
input double       InpBreakEvenLockPoints = 50;        // 推保本时锁定的利润点数
input bool         InpUseTrailingStop = true;          // 启用移动止盈/移动止损
input TakeProfitMode InpTakeProfitMode = TP_USE_TP1;   // 固定止盈方式：TP1、TP2 或不设固定止盈
input double       InpTrailStartPoints = 4000;          // 浮盈达到该点数后，启动移动止盈
input double       InpTrailDistancePoints = 500;       // 移动止盈距离当前价多少点
input double       InpTrailStepPoints = 200;           // 止损至少改善多少点才修改一次

input group "【六】账户利润保护：净值高水位"
input bool         InpUseEquityProtection = true;      // 启用账户净值高水位保护
input EquityProtectAnchorMode InpEquityProtectAnchorMode = ANCHOR_INITIAL_DEPOSIT; // 门槛基准：见上方三种模式说明
input double       InpEquityProtectStartPercent = 4.0;  // 净值盈利达到基准资金的该百分比后，才开始保护
input double       InpEquityGivebackPercent = 20;      // 从净值高点回吐该百分比后，平掉本 EA 持仓
input int          InpPauseAfterEquityProtectMinutes = 240; // 净值保护触发后，暂停开新仓的分钟数

input group "【七】单日最大亏损保护"
input bool          InpUseDailyMaxLoss = false;              // 启用单日最大亏损保护
input DailyLossMode InpDailyMaxLossMode = DAILY_LOSS_PERCENT; // 亏损限制方式：百分比或固定金额
input double        InpDailyMaxLossPercent = 5.0;            // 单日最大亏损百分比（基于当日开始净值）
input double        InpDailyMaxLossMoney = 500.0;            // 单日最大亏损金额，账户货币，仅在固定金额模式下生效

input group "【八】连续亏损暂停"
input bool         InpUseConsecutiveLossPause = false;        // 启用连续亏损后暂停开仓
input int          InpConsecutiveLossCount = 3;               // 连续亏损达到该笔数后触发暂停
input int          InpPauseAfterConsecutiveLossMinutes = 240; // 触发后暂停开新仓的分钟数

input group "【九】EA 运行设置"
input int          InpTimerSeconds = 10;               // 定时检查间隔，单位：秒
input ulong        InpMagic = 20260530;                // 魔术号，用于区分本 EA 的订单

CTrade trade;
datetime last_h4 = 0;
datetime last_h1 = 0;
datetime last_m15 = 0;
datetime last_m5 = 0;
string last_signal_key[3] = {"", "", ""}; // 按策略分别去重：0=TrendPullback 1=Breakout 2=Reversal
double start_balance = 0.0;
double initial_deposit = 0.0;   // EA 启动时的初始入金，锚定模式下净值保护门槛始终以此为基准，不随触发重置
double g_last_trade_open_balance = 0.0; // 最近一次本 EA 成功开仓时的账户余额，ANCHOR_LAST_TRADE_OPEN 模式下用作基准
double peak_equity = 0.0;
datetime pause_new_entries_until = 0;

// --- 单日最大亏损保护 ---
datetime g_day_start_time = 0;   // 当日开始的时间戳，用于判断是否跨天
double   g_day_start_equity = 0.0; // 当日开始时的净值，作为亏损计算基准
bool     g_daily_loss_halt = false; // 当日是否已触发亏损保护（触发后当日不再开新仓）

// --- 连续亏损暂停 ---
int      g_consecutive_losses = 0;     // 连续亏损笔数，出现盈利单后清零
datetime g_pause_consecutive_until = 0; // 连续亏损触发后，暂停开新仓到该时间

// --- Breakout 策略用的 H1 箱体缓存：箱体只在 H1 换新K线时才会变化 ---
double g_box_high = 0.0;
double g_box_low  = 0.0;
bool   g_box_ready = false;

// --- 指标句柄缓存：避免每次调用都新建/释放句柄 ---
#define TF_COUNT 4
ENUM_TIMEFRAMES g_tf_list[TF_COUNT];
int g_ema_fast_handle[TF_COUNT];
int g_ema_slow_handle[TF_COUNT];
int g_rsi_handle[TF_COUNT];

int TFIndex(ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < TF_COUNT; i++)
      if(g_tf_list[i] == tf)
         return i;
   return -1;
}

struct SwingInfo
{
   double recentHigh;
   double prevHigh;
   double recentLow;
   double prevLow;
   int recentHighShift;
   int recentLowShift;
};

struct Signal
{
   bool valid;
   string strategy;
   string side;
   double entry;
   double sl;
   double tp1;
   double tp2;
   string reason;
};

// --- 按周期缓存 Swing/Trend 结果：只有对应周期真正换新K线时才重算，
//     避免大周期（H4/H1）在小周期（M5）每次换根时被反复全量扫描 ---
SwingInfo  g_sw_h4, g_sw_h1, g_sw_m15, g_sw_m5;
TrendState g_trend_h4 = TREND_RANGE, g_trend_h1 = TREND_RANGE, g_trend_m15 = TREND_RANGE, g_trend_m5 = TREND_RANGE;
bool       g_cache_ready = false; // 首次运行前缓存还没有值，需要强制全量计算一次

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_tf_list[0] = InpBigTrendTF;
   g_tf_list[1] = InpTrendTF;
   g_tf_list[2] = InpSetupTF;
   g_tf_list[3] = InpEntryTF;

   for(int i = 0; i < TF_COUNT; i++)
   {
      g_ema_fast_handle[i] = iMA(_Symbol, g_tf_list[i], InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_ema_slow_handle[i] = iMA(_Symbol, g_tf_list[i], InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_rsi_handle[i]      = iRSI(_Symbol, g_tf_list[i], InpRSIPeriod, PRICE_CLOSE);
      if(g_ema_fast_handle[i] == INVALID_HANDLE || g_ema_slow_handle[i] == INVALID_HANDLE || g_rsi_handle[i] == INVALID_HANDLE)
      {
         Print("指标句柄创建失败: ", TFName(g_tf_list[i]));
         return INIT_FAILED;
      }
   }

   start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   initial_deposit = start_balance;
   g_last_trade_open_balance = start_balance;
   peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);

   g_day_start_time = TimeCurrent();
   g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_loss_halt = false;
   g_consecutive_losses = 0;
   g_pause_consecutive_until = 0;

   EventSetTimer(InpTimerSeconds);
   Print("MultiTF Framework Assistant 已启动，品种: ", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < TF_COUNT; i++)
   {
      if(g_ema_fast_handle[i] != INVALID_HANDLE)
         IndicatorRelease(g_ema_fast_handle[i]);
      if(g_ema_slow_handle[i] != INVALID_HANDLE)
         IndicatorRelease(g_ema_slow_handle[i]);
      if(g_rsi_handle[i] != INVALID_HANDLE)
         IndicatorRelease(g_rsi_handle[i]);
   }
   ObjectsDeleteAll(0, "MTF_");
}

ulong g_last_process_ms = 0; // 上次执行核心逻辑的时间戳，用于给 OnTimer 去重

void OnTick()
{
   ProcessCycle(false);
}

void OnTimer()
{
   // 行情密集时 OnTick 触发频率通常远高于 InpTimerSeconds，
   // 如果最近一次 tick 刚处理过（1秒内），这里跳过，避免重复计算；
   // 行情清淡/无tick时（比如周末缺口后），定时器仍会正常兜底执行
   if(GetTickCount64() - g_last_process_ms < 1000)
      return;
   ProcessCycle(true);
}

void ProcessCycle(bool timer_call)
{
   g_last_process_ms = GetTickCount64();
   ManageOpenPositions();
   ManageEquityProtection();
   ManageDailyLoss();
   Analyze(timer_call);
}

//+------------------------------------------------------------------+
//| 交易事务回调：用来统计连续亏损笔数（只统计本 EA、本品种的平仓成交）|
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpUseConsecutiveLossPause)
      return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal_ticket = trans.deal;
   if(!HistoryDealSelect(deal_ticket))
      return;

   string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   ulong magic = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   long entry_type = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

   if(symbol != _Symbol || magic != InpMagic)
      return;
   // 只统计平仓成交（DEAL_ENTRY_OUT / DEAL_ENTRY_OUT_BY），开仓成交不计入盈亏统计
   if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                  + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                  + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

   if(profit < 0.0)
   {
      g_consecutive_losses++;
      Print("连续亏损计数: ", g_consecutive_losses, "/", InpConsecutiveLossCount);
      if(g_consecutive_losses >= InpConsecutiveLossCount)
      {
         g_pause_consecutive_until = TimeCurrent() + InpPauseAfterConsecutiveLossMinutes * 60;
         Print("连续亏损达到阈值，暂停开新仓至: ", TimeToString(g_pause_consecutive_until, TIME_DATE | TIME_MINUTES));
      }
   }
   else if(profit > 0.0)
   {
      g_consecutive_losses = 0; // 出现盈利单，连续亏损计数清零
   }
   // profit == 0（保本出场）不计入亏损也不重置计数，维持中性
}

//+------------------------------------------------------------------+
//| 单日最大亏损保护：跨天自动重置基准，当日亏损达到限制后不再开新仓  |
//+------------------------------------------------------------------+
void ManageDailyLoss()
{
   if(!InpUseDailyMaxLoss)
      return;

   datetime now = TimeCurrent();
   if(IsNewTradingDay(now, g_day_start_time))
   {
      g_day_start_time = now;
      g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_daily_loss_halt = false;
      Print("新交易日开始，重置单日亏损基准净值: ", DoubleToString(g_day_start_equity, 2));
   }

   if(g_daily_loss_halt)
      return; // 今日已触发过，不必重复检查

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss = g_day_start_equity - equity;
   if(loss <= 0.0)
      return;

   double loss_limit = (InpDailyMaxLossMode == DAILY_LOSS_MONEY)
                        ? InpDailyMaxLossMoney
                        : g_day_start_equity * InpDailyMaxLossPercent / 100.0;
   if(loss_limit <= 0.0)
      return;

   if(loss >= loss_limit)
   {
      g_daily_loss_halt = true;
      Print("单日最大亏损触发，今日不再开新仓: 亏损=", DoubleToString(loss, 2),
            " 限额=", DoubleToString(loss_limit, 2),
            " 模式=", (InpDailyMaxLossMode == DAILY_LOSS_MONEY ? "固定金额" : "百分比"));
   }
}

bool IsNewTradingDay(datetime now, datetime last_day_time)
{
   if(last_day_time == 0)
      return true;
   MqlDateTime a, b;
   TimeToStruct(now, a);
   TimeToStruct(last_day_time, b);
   return (a.year != b.year || a.mon != b.mon || a.day != b.day);
}

//+------------------------------------------------------------------+
void Analyze(bool timer_call)
{
   bool h4_new = IsNewBar(InpBigTrendTF, last_h4);
   bool h1_new = IsNewBar(InpTrendTF, last_h1);
   bool m15_new = IsNewBar(InpSetupTF, last_m15);
   bool m5_new = IsNewBar(InpEntryTF, last_m5);

   if(!(h4_new || h1_new || m15_new || m5_new))
      return;

   // SwingInfo/TrendState 只在对应周期真正换新K线时才重算；没换根的周期直接复用缓存，
   // 避免比如 H4 在 M5 每次收盘时都被重复扫描 InpLookbackBars 根K线
   bool force_all = !g_cache_ready;
   if(h4_new || force_all)
   {
      g_sw_h4 = GetSwings(InpBigTrendTF);
      g_trend_h4 = GetTrend(InpBigTrendTF, g_sw_h4);
   }
   if(h1_new || force_all)
   {
      g_sw_h1 = GetSwings(InpTrendTF);
      g_trend_h1 = GetTrend(InpTrendTF, g_sw_h1);
   }
   if(m15_new || force_all)
   {
      g_sw_m15 = GetSwings(InpSetupTF);
      g_trend_m15 = GetTrend(InpSetupTF, g_sw_m15);
   }
   if(m5_new || force_all)
   {
      g_sw_m5 = GetSwings(InpEntryTF);
      g_trend_m5 = GetTrend(InpEntryTF, g_sw_m5);
   }
   g_cache_ready = true;

   SwingInfo sw_h4 = g_sw_h4;
   SwingInfo sw_h1 = g_sw_h1;
   SwingInfo sw_m15 = g_sw_m15;
   SwingInfo sw_m5 = g_sw_m5;

   TrendState h4 = g_trend_h4;
   TrendState h1 = g_trend_h1;
   TrendState m15 = g_trend_m15;
   TrendState m5 = g_trend_m5;

   string summary = StringFormat("多周期分析 %s | %s=%s %s=%s %s=%s %s=%s",
                                 _Symbol, TFName(InpBigTrendTF), TrendName(h4),
                                 TFName(InpTrendTF), TrendName(h1),
                                 TFName(InpSetupTF), TrendName(m15),
                                 TFName(InpEntryTF), TrendName(m5));
   string protect_status = "";
   if(InpUseDailyMaxLoss)
      protect_status += (g_daily_loss_halt ? " | 单日亏损保护:已触发" : " | 单日亏损保护:监控中");
   if(InpUseConsecutiveLossPause)
      protect_status += (TimeCurrent() < g_pause_consecutive_until
                          ? StringFormat(" | 连续亏损暂停中(至%s)", TimeToString(g_pause_consecutive_until, TIME_MINUTES))
                          : StringFormat(" | 连续亏损:%d/%d", g_consecutive_losses, InpConsecutiveLossCount));

   Comment(summary, "\n", "策略: ", ModeName(InpMode), " | 自动交易: ", (InpEnableAutoTrade ? "开启" : "关闭"),
           "\n", "点差: ", DoubleToString(CurrentSpreadPoints(), 1), " points", protect_status);

   if(h1_new || !g_box_ready)
      g_box_ready = CalcH1Box(g_box_high, g_box_low);

   Signal signals[3];
   signals[0] = TrendPullbackSignal(h4, h1, m15, m5, sw_m15, sw_m5);
   signals[1] = BreakoutSignal(h4, h1, m15, m5, sw_m5, g_box_high, g_box_low);
   signals[2] = ReversalSignal(h4, h1, m15, m5, sw_m15, sw_m5);

   if(InpDrawLevels)
      ObjectsDeleteAll(0, "MTF_"); // 每轮分析先清空旧的入场/止损/止盈线，避免图表对象无限堆积

   for(int i = 0; i < 3; i++)
   {
      if(!signals[i].valid)
         continue;
      if(InpMode != MODE_ALL && !ModeAllows(signals[i].strategy))
         continue;

      double rr = RewardRisk(signals[i]);
      if(rr < InpMinRR)
         continue;
      if(!RiskFiltersPass(signals[i]))
         continue;

      string key = StringFormat("%s-%s-%.2f-%.2f-%.2f", signals[i].strategy, signals[i].side,
                                signals[i].entry, signals[i].sl, signals[i].tp1);
      if(key == last_signal_key[i])
         continue;
      last_signal_key[i] = key;

      string msg = StringFormat("%s %s %s | 入场 %.2f 止损 %.2f 止盈1 %.2f 止盈2 %.2f | 盈亏比 %.2f | %s",
                                _Symbol, StrategyCN(signals[i].strategy), SideCN(signals[i].side), signals[i].entry,
                                signals[i].sl, signals[i].tp1, signals[i].tp2, rr, signals[i].reason);
      Print(msg);
      if(InpUseAlerts)
         Alert(msg);
      if(InpDrawLevels)
         DrawSignal(signals[i]);
      if(InpEnableAutoTrade)
         PlaceTrade(signals[i]);
   }
}

//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &last_time)
{
   // 用 iTime 只取第0根K线的时间戳，避免每个 tick 都拷贝/排列一次K线数组
   datetime t = iTime(_Symbol, tf, 0);
   if(t == 0)
      return false;
   if(t != last_time)
   {
      last_time = t;
      return true;
   }
   return false;
}

double MA(ENUM_TIMEFRAMES tf, int period, int shift)
{
   int idx = TFIndex(tf);
   if(idx < 0)
      return 0.0;
   // period 只会是 InpFastEMA 或 InpSlowEMA 之一，对应两套缓存好的句柄
   int handle = (period == InpFastEMA) ? g_ema_fast_handle[idx] : g_ema_slow_handle[idx];
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1)
      return 0.0;
   return buf[0];
}

double RSI(ENUM_TIMEFRAMES tf, int shift)
{
   int idx = TFIndex(tf);
   if(idx < 0)
      return 50.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_rsi_handle[idx], 0, shift, 1, buf) < 1)
      return 50.0;
   return buf[0];
}

bool GetRates(ENUM_TIMEFRAMES tf, MqlRates &rates[], int count)
{
   ArraySetAsSeries(rates, true);
   return CopyRates(_Symbol, tf, 0, count, rates) >= count;
}

SwingInfo GetSwings(ENUM_TIMEFRAMES tf)
{
   SwingInfo s;
   s.recentHigh = s.prevHigh = s.recentLow = s.prevLow = 0.0;
   s.recentHighShift = s.recentLowShift = -1;

   MqlRates rates[];
   int count = MathMax(InpLookbackBars, 40);
   if(!GetRates(tf, rates, count))
      return s;

   int foundH = 0;
   int foundL = 0;
   for(int i = 3; i < count - 3; i++)
   {
      bool high = rates[i].high > rates[i - 1].high && rates[i].high > rates[i - 2].high &&
                  rates[i].high > rates[i + 1].high && rates[i].high > rates[i + 2].high;
      bool low = rates[i].low < rates[i - 1].low && rates[i].low < rates[i - 2].low &&
                 rates[i].low < rates[i + 1].low && rates[i].low < rates[i + 2].low;
      if(high && foundH < 2)
      {
         if(foundH == 0)
         {
            s.recentHigh = rates[i].high;
            s.recentHighShift = i;
         }
         else
            s.prevHigh = rates[i].high;
         foundH++;
      }
      if(low && foundL < 2)
      {
         if(foundL == 0)
         {
            s.recentLow = rates[i].low;
            s.recentLowShift = i;
         }
         else
            s.prevLow = rates[i].low;
         foundL++;
      }
      if(foundH >= 2 && foundL >= 2)
         break;
   }
   return s;
}

TrendState GetTrend(ENUM_TIMEFRAMES tf, const SwingInfo &sw)
{
   double close1 = iClose(_Symbol, tf, 1);
   if(close1 <= 0.0)
      return TREND_RANGE;

   double ema_fast = MA(tf, InpFastEMA, 1);
   double ema_slow = MA(tf, InpSlowEMA, 1);

   bool hh_hl = (sw.recentHigh > sw.prevHigh && sw.recentLow > sw.prevLow && sw.prevHigh > 0 && sw.prevLow > 0);
   bool ll_lh = (sw.recentHigh < sw.prevHigh && sw.recentLow < sw.prevLow && sw.prevHigh > 0 && sw.prevLow > 0);

   if(ema_fast > ema_slow && close1 > ema_slow && hh_hl)
      return TREND_UP;
   if(ema_fast < ema_slow && close1 < ema_slow && ll_lh)
      return TREND_DOWN;
   if(MathAbs(ema_fast - ema_slow) < 2.0 * _Point * 100)
      return TREND_RANGE;
   return TREND_TRANSITION;
}

//+------------------------------------------------------------------+
Signal EmptySignal()
{
   Signal s;
   s.valid = false;
   s.strategy = "";
   s.side = "";
   s.entry = s.sl = s.tp1 = s.tp2 = 0.0;
   s.reason = "";
   return s;
}

Signal TrendPullbackSignal(TrendState h4, TrendState h1, TrendState m15, TrendState m5,
                            const SwingInfo &m15s, const SwingInfo &m5s)
{
   Signal sig = EmptySignal();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ema20_m15 = MA(InpSetupTF, InpFastEMA, 1);
   double ema60_m15 = MA(InpSetupTF, InpSlowEMA, 1);

   bool big_up = (h4 == TREND_UP || h4 == TREND_TRANSITION) && h1 == TREND_UP;
   bool big_down = (h4 == TREND_DOWN || h4 == TREND_TRANSITION) && h1 == TREND_DOWN;

   if(big_up && m15s.recentLow > 0 && bid >= MathMin(ema20_m15, ema60_m15) && m5s.recentHigh > 0 && ask > m5s.recentHigh)
   {
      sig.valid = true;
      sig.strategy = "TrendPullback";
      sig.side = "BUY";
      sig.entry = ask;
      sig.sl = m15s.recentLow - InpSLBufferPoints * _Point;
      sig.tp1 = m15s.recentHigh;
      sig.tp2 = sig.entry + 2.0 * (sig.entry - sig.sl);
      sig.reason = "H1 up, H4 not against; M15 pullback area; M5 breaks minor high.";
   }
   else if(big_down && m15s.recentHigh > 0 && ask <= MathMax(ema20_m15, ema60_m15) && m5s.recentLow > 0 && bid < m5s.recentLow)
   {
      sig.valid = true;
      sig.strategy = "TrendPullback";
      sig.side = "SELL";
      sig.entry = bid;
      sig.sl = m15s.recentHigh + InpSLBufferPoints * _Point;
      sig.tp1 = m15s.recentLow;
      sig.tp2 = sig.entry - 2.0 * (sig.sl - sig.entry);
      sig.reason = "H1 down, H4 not against; M15 pullback area; M5 breaks minor low.";
   }
   return sig;
}

// 计算 H1 箱体高低点，只应在 h1_new 为 true 时调用一次并缓存结果，
// box_high/box_low 由 Analyze() 传给 BreakoutSignal，不再每次都重新拉取36根K线扫描
bool CalcH1Box(double &box_high, double &box_low)
{
   MqlRates h1r[];
   if(!GetRates(InpTrendTF, h1r, 36))
      return false;

   box_high = h1r[2].high;
   box_low = h1r[2].low;
   for(int i = 2; i <= 14; i++)
   {
      box_high = MathMax(box_high, h1r[i].high);
      box_low = MathMin(box_low, h1r[i].low);
   }
   return true;
}

Signal BreakoutSignal(TrendState h4, TrendState h1, TrendState m15, TrendState m5, const SwingInfo &m5s,
                      double box_high, double box_low)
{
   Signal sig = EmptySignal();
   if(box_high <= 0.0 || box_low <= 0.0)
      return sig;

   MqlRates m15r[];
   if(!GetRates(InpSetupTF, m15r, 12))
      return sig;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool up_break = m15r[1].close > box_high + InpBreakoutBufferPoints * _Point;
   bool down_break = m15r[1].close < box_low - InpBreakoutBufferPoints * _Point;

   if(up_break && ask > m5s.recentHigh && (h4 != TREND_DOWN || h1 == TREND_UP))
   {
      sig.valid = true;
      sig.strategy = "Breakout";
      sig.side = "BUY";
      sig.entry = ask;
      sig.sl = box_high - InpSLBufferPoints * _Point;
      sig.tp1 = sig.entry + (box_high - box_low);
      sig.tp2 = sig.entry + 2.0 * (sig.entry - sig.sl);
      sig.reason = "M15 closes above H1 box; M5 confirms continuation.";
   }
   else if(down_break && bid < m5s.recentLow && (h4 != TREND_UP || h1 == TREND_DOWN))
   {
      sig.valid = true;
      sig.strategy = "Breakout";
      sig.side = "SELL";
      sig.entry = bid;
      sig.sl = box_low + InpSLBufferPoints * _Point;
      sig.tp1 = sig.entry - (box_high - box_low);
      sig.tp2 = sig.entry - 2.0 * (sig.sl - sig.entry);
      sig.reason = "M15 closes below H1 box; M5 confirms continuation.";
   }
   return sig;
}

Signal ReversalSignal(TrendState h4, TrendState h1, TrendState m15, TrendState m5,
                       const SwingInfo &m15s, const SwingInfo &m5s)
{
   Signal sig = EmptySignal();
   MqlRates m15r[];
   if(!GetRates(InpSetupTF, m15r, 2)) // 只需要 m15r[1].close，不必拷贝80根
      return sig;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double rsi_now = RSI(InpSetupTF, 1);
   double rsi_old = RSI(InpSetupTF, 10);
   double ema20_setup = MA(InpSetupTF, InpFastEMA, 1);
   double ema60_setup = MA(InpSetupTF, InpSlowEMA, 1);

   bool bullish_div = m15s.recentLow < m15s.prevLow && rsi_now > rsi_old && rsi_old <= InpReversalBuyRsiMax;
   bool bearish_div = m15s.recentHigh > m15s.prevHigh && rsi_now < rsi_old && rsi_old >= InpReversalSellRsiMin;
   bool buy_setup_close = (InpReversalRequireEMA60 ? m15r[1].close > ema60_setup : m15r[1].close > ema20_setup);
   bool sell_setup_close = (InpReversalRequireEMA60 ? m15r[1].close < ema60_setup : m15r[1].close < ema20_setup);
   bool buy_entry_break = m5s.recentHigh > 0 && ask > m5s.recentHigh + InpReversalBreakBufferPoints * _Point;
   bool sell_entry_break = m5s.recentLow > 0 && bid < m5s.recentLow - InpReversalBreakBufferPoints * _Point;

   if((h4 == TREND_DOWN || h1 == TREND_DOWN || h4 == TREND_TRANSITION) && bullish_div &&
      buy_setup_close && buy_entry_break)
   {
      sig.valid = true;
      sig.strategy = "Reversal";
      sig.side = "BUY";
      sig.entry = ask;
      sig.sl = m15s.recentLow - InpSLBufferPoints * _Point;
      sig.tp1 = (m15s.recentHigh > sig.entry ? m15s.recentHigh : sig.entry + InpMinRR * (sig.entry - sig.sl));
      sig.tp2 = sig.entry + 2.0 * (sig.entry - sig.sl);
      sig.reason = "Strict reversal BUY: setup RSI divergence, close above required EMA, entry timeframe breaks minor high with buffer.";
   }
   else if((h4 == TREND_UP || h1 == TREND_UP || h4 == TREND_TRANSITION) && bearish_div &&
           sell_setup_close && sell_entry_break)
   {
      sig.valid = true;
      sig.strategy = "Reversal";
      sig.side = "SELL";
      sig.entry = bid;
      sig.sl = m15s.recentHigh + InpSLBufferPoints * _Point;
      sig.tp1 = (m15s.recentLow < sig.entry ? m15s.recentLow : sig.entry - InpMinRR * (sig.sl - sig.entry));
      sig.tp2 = sig.entry - 2.0 * (sig.sl - sig.entry);
      sig.reason = "Strict reversal SELL: setup RSI divergence, close below required EMA, entry timeframe breaks minor low with buffer.";
   }
   return sig;
}

//+------------------------------------------------------------------+
double RewardRisk(Signal &s)
{
   if(!s.valid)
      return 0.0;
   double risk = MathAbs(s.entry - s.sl);
   double reward = MathAbs(s.tp1 - s.entry);
   if(risk <= 0.0)
      return 0.0;
   return reward / risk;
}

bool ModeAllows(string strategy)
{
   if(InpMode == MODE_TREND_PULLBACK && strategy == "TrendPullback")
      return true;
   if(InpMode == MODE_BREAKOUT_CONTINUATION && strategy == "Breakout")
      return true;
   if(InpMode == MODE_REVERSAL_CONFIRMATION && strategy == "Reversal")
      return true;
   return false;
}

void DrawSignal(Signal &s)
{
   string prefix = "MTF_" + s.strategy + "_" + s.side + "_";
   DrawHLine(prefix + "ENTRY", s.entry, clrDodgerBlue, STYLE_SOLID);
   DrawHLine(prefix + "SL", s.sl, clrTomato, STYLE_DASH);
   DrawHLine(prefix + "TP1", s.tp1, clrLimeGreen, STYLE_DOT);
   DrawHLine(prefix + "TP2", s.tp2, clrGreen, STYLE_DOT);
}

void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

void ManageOpenPositions()
{
   // 两个功能都没开的话，整个持仓循环都没有意义，直接跳过
   if(!InpUseBreakEven && !InpUseTrailingStop)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != InpMagic)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double old_sl = PositionGetDouble(POSITION_SL);
      double old_tp = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double new_sl = old_sl;

      if(type == POSITION_TYPE_BUY)
      {
         double profit_points = (bid - open_price) / _Point;

         if(InpUseBreakEven && profit_points >= InpBreakEvenStartPoints)
         {
            double be_sl = NormalizeDouble(open_price + InpBreakEvenLockPoints * _Point, _Digits);
            if((old_sl <= 0.0 || be_sl > old_sl) && bid - be_sl > stop_level)
               new_sl = be_sl;
         }

         if(InpUseTrailingStop && profit_points >= InpTrailStartPoints)
         {
            double trail_sl = NormalizeDouble(bid - InpTrailDistancePoints * _Point, _Digits);
            if((new_sl <= 0.0 || trail_sl > new_sl + InpTrailStepPoints * _Point) && bid - trail_sl > stop_level)
               new_sl = trail_sl;
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profit_points = (open_price - ask) / _Point;

         if(InpUseBreakEven && profit_points >= InpBreakEvenStartPoints)
         {
            double be_sl = NormalizeDouble(open_price - InpBreakEvenLockPoints * _Point, _Digits);
            if((old_sl <= 0.0 || be_sl < old_sl) && be_sl - ask > stop_level)
               new_sl = be_sl;
         }

         if(InpUseTrailingStop && profit_points >= InpTrailStartPoints)
         {
            double trail_sl = NormalizeDouble(ask + InpTrailDistancePoints * _Point, _Digits);
            if((new_sl <= 0.0 || trail_sl < new_sl - InpTrailStepPoints * _Point) && trail_sl - ask > stop_level)
               new_sl = trail_sl;
         }
      }

      if(new_sl > 0.0 && MathAbs(new_sl - old_sl) >= InpTrailStepPoints * _Point)
      {
         if(!trade.PositionModify(ticket, new_sl, old_tp))
            Print("移动止盈修改失败: ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }
}

void ManageEquityProtection()
{
   if(!InpUseEquityProtection)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > peak_equity)
      peak_equity = equity;

   // protect_base：三种模式共用同一个基准，既决定"武装门槛"，也决定净值高点的起算点——
   //   ANCHOR_INITIAL_DEPOSIT：固定用 EA 启动时的初始入金
   //   ANCHOR_ROLLING_AFTER_TRIGGER：用当前周期起始余额（每次触发保护后滚动更新）
   //   ANCHOR_LAST_TRADE_OPEN：用最近一次本 EA 开仓时的余额（peak_equity 也会在每次新开仓时同步重置）
   double protect_base;
   string anchor_name;
   if(InpEquityProtectAnchorMode == ANCHOR_LAST_TRADE_OPEN)
   {
      protect_base = g_last_trade_open_balance;
      anchor_name = "最近开仓余额";
   }
   else if(InpEquityProtectAnchorMode == ANCHOR_ROLLING_AFTER_TRIGGER)
   {
      protect_base = start_balance;
      anchor_name = "滚动余额";
   }
   else
   {
      protect_base = initial_deposit;
      anchor_name = "初始入金";
   }

   // peak_profit 统一用 protect_base 计算，而不是固定用 start_balance——
   // 这样三种模式才会真正体现出不同的保护效果，而不只是门槛数字不同
   double peak_profit = peak_equity - protect_base;
   double start_profit = protect_base * InpEquityProtectStartPercent / 100.0;
   if(peak_profit < start_profit)
      return;

   double giveback_money = peak_equity - equity;
   double allowed_giveback = peak_profit * InpEquityGivebackPercent / 100.0;
   if(giveback_money >= allowed_giveback)
   {
      Print("账户净值保护触发: peak_equity=", DoubleToString(peak_equity, 2),
            " equity=", DoubleToString(equity, 2),
            " giveback=", DoubleToString(giveback_money, 2),
            " base=", DoubleToString(protect_base, 2),
            " anchor_mode=", anchor_name);
      CloseOurPositions();
      pause_new_entries_until = TimeCurrent() + InpPauseAfterEquityProtectMinutes * 60;
      peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   }
}

void CloseOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol == _Symbol && magic == InpMagic)
      {
         if(!trade.PositionClose(ticket))
            Print("净值保护平仓失败: ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }
}

void PlaceTrade(Signal &s)
{
   if(CountOurPositions() >= InpMaxOpenPositions)
   {
      Print("已有本 EA 持仓，跳过新开仓: ", _Symbol);
      return;
   }

   double lots = CalculateLots(s);
   if(lots <= 0.0)
   {
      Print("手数计算失败，跳过交易: ", _Symbol);
      return;
   }

   double sl = NormalizeDouble(s.sl, _Digits);
   double tp = OrderTakeProfit(s);
   double balance_before_open = AccountInfoDouble(ACCOUNT_BALANCE);
   bool ok = false;
   if(s.side == "BUY")
      ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, s.strategy);
   else if(s.side == "SELL")
      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, s.strategy);

   if(ok)
   {
      // 记录本次开仓时的余额，供 ANCHOR_LAST_TRADE_OPEN 模式的净值保护使用
      g_last_trade_open_balance = balance_before_open;
      if(InpEquityProtectAnchorMode == ANCHOR_LAST_TRADE_OPEN)
      {
         // 新一笔交易开始，净值高点也从这里重新起算，
         // 避免沿用上一笔交易周期遗留的净值高点，导致新仓一开就被判定"回吐过多"而被秒平
         peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
      Print("自动开仓成功: ", _Symbol, " ", s.side, " lots=", DoubleToString(lots, 2), " SL=", sl, " TP=", tp);
   }
   else
      Print("自动开仓失败: retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

double OrderTakeProfit(Signal &s)
{
   if(InpTakeProfitMode == TP_NO_FIXED)
      return 0.0;
   if(InpTakeProfitMode == TP_USE_TP2)
      return NormalizeDouble(s.tp2, _Digits);
   return NormalizeDouble(s.tp1, _Digits);
}

double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return 999999.0;
   return (ask - bid) / _Point;
}

bool RiskFiltersPass(Signal &s)
{
   if(TimeCurrent() < pause_new_entries_until)
   {
      Print("净值保护暂停期内，跳过新信号。恢复时间: ", TimeToString(pause_new_entries_until, TIME_DATE | TIME_MINUTES));
      return false;
   }

   if(InpUseDailyMaxLoss && g_daily_loss_halt)
   {
      Print("单日最大亏损已触发，今日不再开新仓。");
      return false;
   }

   if(InpUseConsecutiveLossPause && TimeCurrent() < g_pause_consecutive_until)
   {
      Print("连续亏损暂停期内，跳过新信号。恢复时间: ", TimeToString(g_pause_consecutive_until, TIME_DATE | TIME_MINUTES));
      return false;
   }

   // 止损方向合理性校验：BUY止损必须在入场价下方，SELL止损必须在入场价上方
   if((s.side == "BUY" && s.sl >= s.entry) || (s.side == "SELL" && s.sl <= s.entry))
   {
      Print("止损方向异常，跳过信号: side=", s.side, " entry=", s.entry, " sl=", s.sl);
      return false;
   }

   if(CurrentSpreadPoints() > InpMaxSpreadPoints)
   {
      Print("点差过大，跳过信号: ", DoubleToString(CurrentSpreadPoints(), 1));
      return false;
   }

   double sl_points = MathAbs(s.entry - s.sl) / _Point;
   if(sl_points < InpMinSLPoints)
   {
      Print("止损距离太近，跳过信号: ", DoubleToString(sl_points, 1));
      return false;
   }
   if(sl_points > InpMaxSLPoints)
   {
      Print("止损距离太远，跳过信号: ", DoubleToString(sl_points, 1));
      return false;
   }
   return true;
}

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol == _Symbol && magic == InpMagic)
         count++;
   }
   return count;
}

double CalculateLots(Signal &s)
{
   if(!InpUseRiskPercent)
      return NormalizeLots(InpFixedLots);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * InpRiskPercent / 100.0;
   double risk_points = MathAbs(s.entry - s.sl) / _Point;
   if(risk_money <= 0.0 || risk_points <= 0.0)
      return 0.0;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0)
      return NormalizeLots(InpFixedLots);

   double loss_per_lot = MathAbs(s.entry - s.sl) / tick_size * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;

   return NormalizeLots(risk_money / loss_per_lot);
}

double NormalizeLots(double lots)
{
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   lots = MathMax(min_lot, MathMin(max_lot, lots));
   lots = MathFloor(lots / step) * step;
   int digits = 2;
   if(step < 0.01)
      digits = 3;
   if(step < 0.001)
      digits = 4;
   return NormalizeDouble(lots, digits);
}

string TrendName(TrendState s)
{
   if(s == TREND_UP)
      return "UP上涨";
   if(s == TREND_DOWN)
      return "DOWN下跌";
   if(s == TREND_TRANSITION)
      return "TRANSITION转换";
   return "RANGE震荡";
}

string ModeName(StrategyMode mode)
{
   if(mode == MODE_TREND_PULLBACK)
      return "顺势回调";
   if(mode == MODE_BREAKOUT_CONTINUATION)
      return "突破延续";
   if(mode == MODE_REVERSAL_CONFIRMATION)
      return "反转确认";
   return "全部";
}

string TFName(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)
      return "M1";
   if(tf == PERIOD_M2)
      return "M2";
   if(tf == PERIOD_M3)
      return "M3";
   if(tf == PERIOD_M4)
      return "M4";
   if(tf == PERIOD_M5)
      return "M5";
   if(tf == PERIOD_M6)
      return "M6";
   if(tf == PERIOD_M10)
      return "M10";
   if(tf == PERIOD_M12)
      return "M12";
   if(tf == PERIOD_M15)
      return "M15";
   if(tf == PERIOD_M20)
      return "M20";
   if(tf == PERIOD_M30)
      return "M30";
   if(tf == PERIOD_H1)
      return "H1";
   if(tf == PERIOD_H2)
      return "H2";
   if(tf == PERIOD_H3)
      return "H3";
   if(tf == PERIOD_H4)
      return "H4";
   if(tf == PERIOD_H6)
      return "H6";
   if(tf == PERIOD_H8)
      return "H8";
   if(tf == PERIOD_H12)
      return "H12";
   if(tf == PERIOD_D1)
      return "D1";
   if(tf == PERIOD_W1)
      return "W1";
   if(tf == PERIOD_MN1)
      return "MN1";
   return IntegerToString((int)tf);
}

string StrategyCN(string strategy)
{
   if(strategy == "TrendPullback")
      return "顺势回调";
   if(strategy == "Breakout")
      return "突破延续";
   if(strategy == "Reversal")
      return "反转确认";
   return strategy;
}

string SideCN(string side)
{
   if(side == "BUY")
      return "做多";
   if(side == "SELL")
      return "做空";
   return side;
}
