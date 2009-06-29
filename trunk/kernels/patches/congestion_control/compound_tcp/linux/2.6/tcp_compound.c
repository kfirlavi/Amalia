/*
 *   TCP Compound.  Implementation based on TCP Vegas
 *
 *   further details can be found here:
 *      ftp://ftp.research.microsoft.com/pub/tr/TR-2005-86.pdf
 *   earlier release, requested to go in 2.6.18:
 *	http://lwn.net/Articles/185074/
 *
 * Jan 2008:  Module parameters added -- LA
 * Dec 2007:  Gamma tuning added -- LA
 * Nov 2007:  Disable reset of baseRTT in  tcp_compound_cwnd_event() -- LA
 * Nov 2007:  Port to 2.6.23 -- Lachlan Andrew
 * May 2006:  Original release -- Angelo P. Castellani, Stephen Hemminger
 */

#define TRANSPORT_DEBUG 0

//#include <linux/config.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/inet_diag.h>

#include <net/tcp.h>

/* Default values of the CTCP variables */

/* Fixed point, used by  diff_reno, diff and target_cwnd */
#define C_PARAM_SHIFT 1

static unsigned int LOG_ALPHA __read_mostly = 3U;	/* alpha = 1/8 */
static unsigned int ETA       __read_mostly = 1U;
static int GAMMA              __read_mostly = 30;
static int GAMMA_LOW          __read_mostly = 5;
static int GAMMA_HIGH         __read_mostly = 30;
static int LAMBDA_SHIFT       __read_mostly = 1;	/* lambda = 1/2 */

module_param(    LOG_ALPHA, int, 0644);
MODULE_PARM_DESC(LOG_ALPHA, "Factor of WND^0.75 by which DWND increases");
module_param(    ETA,  int, 0644);
MODULE_PARM_DESC(ETA,  "Factor of estimated queue by which DWND decreases");
module_param(    GAMMA, int, 0644);
MODULE_PARM_DESC(GAMMA, "Delay threshold (pks)");
module_param(    GAMMA_LOW, int, 0644);
MODULE_PARM_DESC(GAMMA_LOW, "GAMMA tuning: min value possible");
module_param(    GAMMA_HIGH, int, 0644);
MODULE_PARM_DESC(GAMMA_LOW, "GAMMA tuning: max value possible");
module_param(    LAMBDA_SHIFT, int, 0644);
MODULE_PARM_DESC(LAMBDA_SHIFT, "GAMMA tuning: log_2(Forgetting factor)");

/* TCP compound variables */
struct compound {
	u32 beg_snd_nxt;	/* right edge during last RTT */
	u32 beg_snd_una;	/* left  edge during last RTT */
	u32 beg_cwnd;		/* saves the size of cwnd only (gamma tuning) */
	u8  doing_ctcp_now;	/* if true, do ctcp for this RTT */
	u16 cntRTT;		/* # of RTTs measured within last RTT */
	u32 minRTT;		/* min of RTTs measured within last RTT (in usec) */
	u32 baseRTT;		/* the min of all CTCP RTT measurements seen (in usec) */

	u32 cwnd;
	u32 dwnd;
	s32 diff_reno;		/* used for gamma-tuning. << C_PARAM_SHIFT */
							/* -1 = invalid */
	u16 gamma;		/* target packets to store in the network */
};

/* There are several situations when we must "re-start" CTCP:
 *
 *  o when a connection is established
 *  o after an RTO
 *  o after fast recovery
 *  o when we send a packet and there is no outstanding
 *    unacknowledged data (restarting an idle connection)
 *
 * In these circumstances we cannot do a CTCP calculation at the
 * end of the first RTT, because any calculation we do is using
 * stale info -- both the saved cwnd and congestion feedback are
 * stale.
 *
 * Instead we must wait until the completion of an RTT during
 * which we actually receive ACKs.
 */
static inline void ctcp_enable(struct sock *sk)
{
	const struct tcp_sock *tp = tcp_sk(sk);
	struct compound *ctcp = inet_csk_ca(sk);

	/* Begin taking CTCP samples next time we send something. */
	ctcp->doing_ctcp_now = 1;

	/* Set the beginning of the next send window. */
	ctcp->beg_snd_nxt = tp->snd_nxt;

	ctcp->cntRTT = 0;
	ctcp->minRTT = 0x7fffffff;
	ctcp->diff_reno = -1;		/* set to invalid */
}

/* Stop taking CTCP samples for now. */
static inline void ctcp_disable(struct sock *sk)
{
	struct compound *ctcp = inet_csk_ca(sk);

	ctcp->doing_ctcp_now = 0;
}

/* Initialize a connection.  Not called when restarted after timeout etc */
static void tcp_compound_init(struct sock *sk)
{
	struct compound *ctcp = inet_csk_ca(sk);
	const struct tcp_sock *tp = tcp_sk(sk);

	ctcp->baseRTT = 0x7fffffff;
	ctcp_enable(sk);

	ctcp->dwnd = 0;
	ctcp->cwnd = tp->snd_cwnd;

	ctcp->gamma = GAMMA;
	ctcp->diff_reno = -1;		/* set to invalid */

}

/* slow start threshold < cwnd/2 like tcp_reno_ssthresh, */
/* but also do gamma tuning */
/* Should it also reduce  dwnd  as specified in CTCP draft?? */
u32 tcp_compound_ssthresh(struct sock *sk)
{
	struct compound *ctcp = inet_csk_ca(sk);
	const struct tcp_sock *tp = tcp_sk(sk);

	/* If  diff_reno  valid, do gamma tuning */
	if (ctcp->diff_reno != -1) {
		/* g_sample = diff_reno * 3/4 */
		u32 g_sample = (ctcp->diff_reno * 3) >> (C_PARAM_SHIFT+2);
		ctcp->gamma += (g_sample - ctcp->gamma) >> LAMBDA_SHIFT;

		/* clip */
		if (ctcp->gamma > GAMMA_HIGH)
		    ctcp->gamma = GAMMA_HIGH;
		else if (ctcp->gamma < GAMMA_LOW)
			 ctcp->gamma = GAMMA_LOW;
		/* don't use one  diff_reno  m'ment for multiple adjustments */
		ctcp->diff_reno = -1;
	}

	/* halve window on loss */
	return max(tp->snd_cwnd >> 1U, 2U);
}

/* Do RTT sampling needed for CTCP.
 * Basically we:
 *   o min-filter RTT samples from within an RTT to get the current
 *     propagation delay + queuing delay (we are min-filtering to try to
 *     avoid the effects of delayed ACKs)
 *   o min-filter RTT samples from a much longer window (forever for now)
 *     to find the propagation delay (baseRTT)
 *
 * Should also deal with active drop under Early Congestion Indication.
 */
static void tcp_compound_pkts_acked(struct sock *sk, u32 num_acked, s32 rtt_us)
{
	struct compound *ctcp = inet_csk_ca(sk);
	struct tcp_sock *tp = tcp_sk(sk);
	u32 vrtt;

	/* ignore dubious RTT measurement */
	if (rtt_us < 0)
		return;

	/* Never allow zero rtt or baseRTT */
	vrtt = rtt_us + 1;

	/* Filter to find propagation delay: */
	if (vrtt < ctcp->baseRTT)
	{
		ctcp->baseRTT = vrtt;
#ifdef LACHLAN_WEB100
		WEB100_VAR_SET(tp, BaseRTT, ctcp->baseRTT);
#endif
	}	

	/* Find the min RTT during the last RTT to find
	 * the current prop. delay + queuing delay:
	 */

	ctcp->minRTT = min(ctcp->minRTT, vrtt);
	ctcp->cntRTT++;
}

static void tcp_compound_state(struct sock *sk, u8 ca_state)
{

	if (ca_state == TCP_CA_Open)
		ctcp_enable(sk);
	else
		ctcp_disable(sk);
}


/* 64bit divisor, dividend and result. dynamic precision */
static inline u64 div64_64_optimized(u64 dividend, u64 divisor)
{
	u32 d = divisor;

	if (divisor > 0xffffffffULL) {
		unsigned int shift = fls(divisor >> 32);

		d = divisor >> shift;
		dividend >>= shift;
	}

	/* avoid 64 bit division if possible */
	if (dividend >> 32)
		do_div(dividend, d);
	else
		dividend = (u32) dividend / d;

	return dividend;
}

/* calculate the quartic root of "a" using Newton-Raphson */
static u32 qroot(u64 a)
{
	u32 x, x1;

	/* Initial estimate is based on:
	 * qrt(x) = exp(log(x) / 4)
	 */
	x = 1u << (fls64(a) >> 2);

	/*
	 * Iteration based on:
	 *                         3
	 * x    = ( 3 * x  +  a / x  ) / 4
	 *  k+1          k         k
	 */
	do {
		u64 x3 = x;

		x1 = x;
		x3 *= x;
		x3 *= x;

		x = (3 * x + (u32) div64_64_optimized(a, x3)) / 4;
	} while (abs(x1 - x) > 1);

	return x;
}


/*
 * If the connection is idle and we are restarting,
 * then we don't want to do any CTCP calculations
 * until we get fresh RTT samples.  So when we
 * restart, we reset our CTCP state to a clean
 * slate. After we get acks for this flight of
 * packets, _then_ we can make CTCP calculations
 * again.
 */
static void tcp_compound_cwnd_event(struct sock *sk, enum tcp_ca_event event)
{
	if (event == CA_EVENT_CWND_RESTART || event == CA_EVENT_TX_START)
	{
		struct compound *ctcp = inet_csk_ca(sk);
		int tmp = ctcp->baseRTT;	/* CTCP spec keeps baseRTT */
		tcp_compound_init(sk);
		//if (event == CA_EVENT_CWND_RESTART)
		ctcp->baseRTT = tmp;
	}
}

static void tcp_compound_cong_avoid(struct sock *sk, u32 ack,
				    u32 in_flight, int flag)
{
	struct tcp_sock *tp = tcp_sk(sk);
	struct compound *ctcp = inet_csk_ca(sk);
	u8 inc = 0;

	/* Update  ctcp->cwnd  to reflect external decreases in  snd_cwnd */
	/* Does this also reflect the "beta" change on loss?? -- LA 16-Jan-08 */
	if (ctcp->cwnd + ctcp->dwnd > tp->snd_cwnd) {
		if (ctcp->cwnd > tp->snd_cwnd || ctcp->dwnd > tp->snd_cwnd) {
			ctcp->cwnd = tp->snd_cwnd;
			ctcp->dwnd = 0;
		} else
			ctcp->cwnd = tp->snd_cwnd - ctcp->dwnd;

	}

	if (!tcp_is_cwnd_limited(sk, in_flight))
		return;

	/* Why does this not call  tcp_slow_start(tp)  and/or consider  abc? */
	/* Is it because it increases  ctcp->cwnd  instead of  tp->snd_cwnd? */
	/* Perhaps:
	   in slow start, call slow_start()  and set  ctcp->cwnd=snd_cwnd - dwdn
	   otherwise, do  abc  stuff to  ctcp->cwnd
	   */
	if (ctcp->cwnd <= tp->snd_ssthresh)
		inc = 1;
	else if (tp->snd_cwnd_cnt < tp->snd_cwnd)
		tp->snd_cwnd_cnt++;

	if (tp->snd_cwnd_cnt >= tp->snd_cwnd) {
		inc = 1;
		tp->snd_cwnd_cnt = 0;
	}

	if (inc && tp->snd_cwnd < tp->snd_cwnd_clamp)
		ctcp->cwnd++;

	/* The key players are v_beg_snd_una and v_beg_snd_nxt.
	 *
	 * These are so named because they represent the approximate values
	 * of snd_una and snd_nxt at the beginning of the current RTT. More
	 * precisely, they represent the amount of data sent during the RTT.
	 * At the end of the RTT, when we receive an ACK for v_beg_snd_nxt,
	 * we will calculate that (v_beg_snd_nxt - v_beg_snd_una) outstanding
	 * bytes of data have been ACKed during the course of the RTT, giving
	 * an "actual" rate of:
	 *
	 *     (v_beg_snd_nxt - v_beg_snd_una) / (rtt duration)
	 *
	 * Unfortunately, v_beg_snd_una is not exactly equal to snd_una,
	 * because delayed ACKs can cover more than one segment, so they
	 * don't line up nicely with the boundaries of RTTs.
	 *
	 */

	if (after(ack, ctcp->beg_snd_nxt)) {
		/* Do the CTCP once-per-RTT cwnd adjustment. */
		u32 old_wnd, old_cwnd;

		/* Here old_wnd is essentially the window of data that was
		 * sent during the previous RTT, and has all
		 * been acknowledged in the course of the RTT that ended
		 * with the ACK we just received. Likewise, old_snd_cwnd
		 * is the cwnd during the previous RTT.
		 */
		if (!tp->mss_cache)
			return;

		old_wnd = (ctcp->beg_snd_nxt - ctcp->beg_snd_una) /
		    tp->mss_cache;
		old_cwnd = ctcp->beg_cwnd;

		/* Save the extent of the current window so we can use this
		 * at the end of the next RTT.
		 */
		ctcp->beg_snd_una = ctcp->beg_snd_nxt;
		ctcp->beg_snd_nxt = tp->snd_nxt;
		ctcp->beg_cwnd = ctcp->cwnd;

		/* We do the CTCP calculations only if we got enough RTT
		 * samples that we can be reasonably sure that we got
		 * at least one RTT sample that wasn't from a delayed ACK.
		 * If we only had 2 samples total,
		 * then that means we're getting only 1 ACK per RTT, which
		 * means they're almost certainly delayed ACKs.
		 * If  we have 3 samples, we should be OK.
		 */

		if (ctcp->cntRTT > 2) {
			u32 rtt, brtt, dwnd;
			u32 target_cwnd, diff; 	/* shifted by C_PARAM_SHIFT */

			/* We have enough RTT samples, so, using the CTCP
			 * algorithm, we determine if we should increase or
			 * decrease cwnd, and by how much.
			 */

			/* Pluck out the RTT we are using for the CTCP
			 * calculations. This is the min RTT seen during the
			 * last RTT. Taking the min filters out the effects
			 * of delayed ACKs, at the cost of noticing congestion
			 * a bit later.
			 */
			rtt = ctcp->minRTT;
#ifdef LACHLAN_WEB100
			WEB100_VAR_SET(tp, EstQ, rtt - ctcp->baseRTT);
#endif

			/* Calculate the cwnd we should have, if we weren't
			 * going too fast.
			 *
			 * This is:
			 *     (actual rate in segments) * baseRTT
			 * We keep it as a fixed point number with
			 * C_PARAM_SHIFT bits to the right of the binary point.
			 */
			if (!rtt)
				return;

			brtt = ctcp->baseRTT;
			target_cwnd = ((old_wnd * brtt) << C_PARAM_SHIFT) / rtt;

			/* Calculate the difference between the window we had,
			 * and the window we would like to have. This quantity
			 * is the "Diff" from the Arizona Vegas papers.
			 *
			 * Again, this is a fixed point number with
			 * C_PARAM_SHIFT bits to the right of the binary
			 * point.
			 */

			diff = (old_wnd << C_PARAM_SHIFT) - target_cwnd;
#ifdef LACHLAN_WEB100
			/* Hacky re-use of AI and MD */
			WEB100_VAR_SET(tp, CurAI, diff);
#endif

			/* Analogously find "diff_reno" for gamma tuning */
			/* This time, use   old_cwnd   instead of  old_wnd */
			target_cwnd = ((old_cwnd* brtt) << C_PARAM_SHIFT) / rtt;
			ctcp->diff_reno =
				(old_cwnd << C_PARAM_SHIFT) - target_cwnd;

			dwnd = ctcp->dwnd;

			if (diff < (ctcp->gamma << C_PARAM_SHIFT)) {
				u64 v;
				u32 x;

				/*
				 * The TCP Compound paper describes the choice
				 * of "k" determines the agressiveness,
				 * ie. slope of the response function.
				 *
				 * For same value as HSTCP would be 0.8
				 * but for computaional reasons, both the
				 * original authors and this implementation
				 * use 0.75.
				 */
				v = old_wnd;
				x = qroot(v * v * v) >> LOG_ALPHA;
				if (x > 1)
					dwnd = x - 1;
				else
					dwnd = 0;

				dwnd += ctcp->dwnd;

			/* Reduce dwnd by  eta * "window diff" */
			/* Recall here diff = "window diff" << C_PARAM_SHIFT */
			} else if ((dwnd << C_PARAM_SHIFT) < (diff * ETA))
				dwnd = 0;
			else
				dwnd =
				    ((dwnd << C_PARAM_SHIFT) - (diff * ETA))
					     >> C_PARAM_SHIFT;

			ctcp->dwnd = dwnd;

		}

		/* Wipe the slate clean for the next RTT. */
		ctcp->cntRTT = 0;
		ctcp->minRTT = 0x7fffffff;
	}

	tp->snd_cwnd = ctcp->cwnd + ctcp->dwnd;
#ifdef LACHLAN_WEB100
	/* Hacky re-use of AI and MD */
	WEB100_VAR_SET(tp, CurMD, ctcp->gamma);
#endif
}

/* Extract info for Tcp socket info provided via netlink. */
static void tcp_compound_get_info(struct sock *sk, u32 ext, struct sk_buff *skb)
{
	const struct compound *ca = inet_csk_ca(sk);
	if (ext & (1 << (INET_DIAG_VEGASINFO - 1))) {
		struct tcpvegas_info info = {
			.tcpv_enabled = ca->doing_ctcp_now,
			.tcpv_rttcnt = ca->cntRTT,
			.tcpv_rtt = ca->baseRTT,
			.tcpv_minrtt = ca->minRTT,
		};

		nla_put(skb, INET_DIAG_VEGASINFO, sizeof(info), &info);
	}
}

static struct tcp_congestion_ops tcp_compound = {
	.flags		= TCP_CONG_RTT_STAMP,
	.init		= tcp_compound_init,
	.ssthresh	= tcp_compound_ssthresh,
	.min_cwnd       = tcp_reno_ssthresh,	/* don't reduce dwnd here */
	.cong_avoid	= tcp_compound_cong_avoid,
	.pkts_acked	= tcp_compound_pkts_acked,
	.set_state	= tcp_compound_state,
	.cwnd_event	= tcp_compound_cwnd_event,
	.get_info	= tcp_compound_get_info,

	.owner		= THIS_MODULE,
	.name		= "compound",
};

static int __init tcp_compound_register(void)
{
	BUG_ON(sizeof(struct compound) > ICSK_CA_PRIV_SIZE);
	tcp_register_congestion_control(&tcp_compound);
	return 0;
}

static void __exit tcp_compound_unregister(void)
{
	tcp_unregister_congestion_control(&tcp_compound);
}

module_init(tcp_compound_register);
module_exit(tcp_compound_unregister);

MODULE_AUTHOR("Angelo P. Castellani, Stephen Hemminger, Lachlan Andrew");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("TCP Compound");
