# amortization_engine.py
# NOW INCLUDES calculate_revolving_debt and calculate_savings_growth

import json
import math
import io
import base64
from typing import Dict, List, Any, Tuple
import pandas as pd
import xlsxwriter

# -----------------------
# Helpers
# -----------------------

def _normalize_rate_input(val) -> float:
    try:
        v = float(val)
    except:
        return 0.0
    return v * 100.0 if 0 < v <= 1 else v

def _parse_rate_changes(text: str) -> Dict[int, float]:
    if not text or not str(text).strip():
        return {}
    out: Dict[int, float] = {}
    for part in str(text).split(","):
        if ":" in part:
            try:
                m, r = part.split(":")
                out[int(m.strip())] = float(r.strip())
            except:
                pass
    return out

def _base_payment_for(balance: float, r_month: float, months_remaining: int) -> float:
    months_remaining = max(1, int(months_remaining))
    if r_month > 0:
        return balance * (r_month * (1 + r_month) ** months_remaining) / (((1 + r_month) ** months_remaining) - 1)
    else:
        return balance / months_remaining

def _generate_yearly_schedule_from_capitalized(hist: List[Dict[str, Any]], initial_principal: float) -> List[Dict[str, Any]]:
    if not hist:
        return [{"year": 0, "payment": 0.0, "principal": 0.0, "interest": 0.0, "balance": round(initial_principal, 2)}]
    df = pd.DataFrame(hist)
    df["Year"] = (df["Month"] - 1) // 12 + 1
    agg = df.groupby("Year").agg(
        Payment=("Payment", "sum"),
        Principal=("Principal", "sum"),
        Interest=("Interest", "sum"),
        Balance=("Balance", "last")
    ).reset_index()
    year0 = pd.DataFrame([{"Year": 0, "Payment": 0.0, "Principal": 0.0, "Interest": 0.0, "Balance": initial_principal}])
    final_df = pd.concat([year0, agg], ignore_index=True)
    final_df = final_df.rename(columns={
        "Year": "year",
        "Payment": "payment",
        "Principal": "principal",
        "Interest": "interest",
        "Balance": "balance"
    })
    return final_df.round(2).to_dict('records')

def _generate_yearly_schedule_from_normalized(monthly_norm: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not monthly_norm:
        return []
    df = pd.DataFrame(monthly_norm)
    if 'month' not in df.columns:
        return []
    df['Year'] = ((df['month'] - 1) // 12) + 1
    agg = df.groupby('Year').agg(
        payment=('payment', 'sum'),
        principal=('principal', 'sum'),
        interest=('interest', 'sum'),
        balance=('balance', 'last')
    ).reset_index().rename(columns={'Year': 'year'})
    return agg.round(2).to_dict('records')

def _generate_chart_data(base_hist: List[Dict[str, Any]], over_hist: List[Dict[str, Any]], principal: float) -> List[Dict[str, Any]]:
    max_months = max(len(base_hist), len(over_hist))
    chart_data: List[Dict[str, Any]] = []
    base_balances = {h['Month']: h['Balance'] for h in base_hist}
    over_balances = {h['Month']: h['Balance'] for h in over_hist}
    for month in range(0, max_months + 1, 6):
        if month == 0:
            base_balance = over_balance = principal
        else:
            base_balance = base_balances.get(month, base_balances.get(month-1, 0.0))
            over_balance = over_balances.get(month, over_balances.get(month-1, 0.0))
            if month > len(base_hist): base_balance = 0.0
            if month > len(over_hist): over_balance = 0.0
        chart_data.append({
            "month": month,
            "baseline_balance": round(base_balance, 2),
            "overpay_balance": round(over_balance, 2),
        })
    return chart_data

def _normalize_monthly_history(hist: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    normalized: List[Dict[str, Any]] = []
    for h in hist:
        month = h.get('month', h.get('Month', 0))
        payment = h.get('payment', h.get('Payment', 0.0))
        principal = h.get('principal', h.get('Principal', 0.0))
        interest = h.get('interest', h.get('Interest', 0.0))
        balance = h.get('balance', h.get('Balance', 0.0))
        try:
            month_i = int(month)
        except:
            month_i = 0
        def tof(x):
            try:
                return float(x)
            except:
                return 0.0
        normalized.append({
            "month": month_i,
            "payment": round(tof(payment), 2),
            "principal": round(tof(principal), 2),
            "interest": round(tof(interest), 2),
            "balance": round(tof(balance), 2)
        })
    return normalized

# -----------------------
# Core Engine
# -----------------------

class AmortizationEngine:
    def _amortize_flexible(
        self,
        principal: float,
        annual_rate_pct: float,
        years: int,
        # overpay strategies
        monthly_overpay: float = 0.0,
        overpay_pct_of_base: float = 0.0,
        annual_lump: float = 0.0,
        annual_lump_month: int = 12,
        one_off_lump: float = 0.0,
        one_off_lump_month: int = 0,
        # rate changes
        rate_changes: Dict[int, float] = None
    ) -> Tuple[List[Dict[str, Any]], float]:
        
        if rate_changes is None:
            rate_changes = {}

        months_total = max(1, int(years * 12))
        balance = float(principal)
        r_annual = float(annual_rate_pct)
        r = r_annual / 100.0 / 12.0

        base_payment = _base_payment_for(balance, r, months_total)
        first_base_payment = base_payment
        history: List[Dict[str, Any]] = []

        for m in range(1, months_total + 20*12): # Add 20 extra years as a buffer
            if balance <= 0:
                break

            if m in rate_changes:
                r_annual = float(rate_changes[m])
                r = r_annual / 100.0 / 12.0
                base_payment = _base_payment_for(balance, r, months_total - m + 1)

            base_now = base_payment
            extra = 0.0
            extra += float(monthly_overpay)
            extra += base_now * (float(overpay_pct_of_base) / 100.0)
            if annual_lump and int(((m - 1) % 12) + 1) == int(annual_lump_month):
                extra += float(annual_lump)
            if one_off_lump and int(m) == int(one_off_lump_month):
                extra += float(one_off_lump)

            interest = balance * r
            actual_payment = base_now + extra

            if balance + interest < actual_payment:
                actual_payment = balance + interest
                principal_paid = balance
                balance = 0.0
            else:
                principal_paid = actual_payment - interest
                balance = max(0.0, balance - principal_paid)

            history.append({
                "Month": m,
                "Payment": round(actual_payment, 2),
                "Principal": round(principal_paid, 2),
                "Interest": round(interest, 2),
                "Balance": round(balance, 2)
            })
            if balance <= 0:
                break
        
        return history, first_base_payment

    def _parse_mortgage_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Parses the 12-field input from Dart."""
        return {
            "principal": float(data.get('loan', 0.0)),
            "annual_rate_pct": _normalize_rate_input(data.get('rate', 0.0)),
            "years": int(data.get('years', 0)),
            "propval": float(data.get('value', 0.0)),
            "monthly_overpay": float(data.get('monthly_overpay', 0.0)),
            "overpay_pct_of_base": float(data.get('overpay_pct_of_base', 0.0)),
            "annual_lump": float(data.get('annual_lump', 0.0)),
            "annual_lump_month": int(data.get('annual_lump_month', 12)),
            "one_off_lump": float(data.get('one_off_lump', 0.0)),
            "one_off_lump_month": int(data.get('one_off_lump_month', 0)),
            "rate_changes": _parse_rate_changes(data.get('rate_changes', '')),
            "inflation": float(data.get('inflation', 0.0))
        }

    def calculate_overpayment_summary(self, data: Dict[str, Any]) -> Dict[str, Any]:
        p = self._parse_mortgage_data(data)
        
        if p['principal'] <= 0 or p['years'] <= 0:
            return {'error': 'Invalid loan amount or years.'}

        sim_inputs = {
            "principal": p['principal'],
            "annual_rate_pct": p['annual_rate_pct'],
            "years": p['years'],
            "monthly_overpay": p['monthly_overpay'],
            "overpay_pct_of_base": p['overpay_pct_of_base'],
            "annual_lump": p['annual_lump'],
            "annual_lump_month": p['annual_lump_month'],
            "one_off_lump": p['one_off_lump'],
            "one_off_lump_month": p['one_off_lump_month'],
            "rate_changes": p['rate_changes']
        }

        base_hist, base_first = self._amortize_flexible(
            principal=p['principal'], annual_rate_pct=p['annual_rate_pct'], years=p['years'],
            rate_changes=p['rate_changes']
        )
        
        over_hist, over_first = self._amortize_flexible(**sim_inputs)
        
        base_interest = sum(h["Interest"] for h in base_hist)
        over_interest = sum(h["Interest"] for h in over_hist)
        base_months = len(base_hist)
        over_months = len(over_hist)
        
        typical_overpay = over_first + p['monthly_overpay'] + (over_first * (p['overpay_pct_of_base'] / 100.0))
        ltv = (p['principal'] / p['propval'] * 100.0) if p['propval'] > 0 else "N/A"
        
        structured_summary = {
            'base_monthly_payment': round(base_first, 2),
            'overpay_monthly_payment': round(typical_overpay, 2),
            'time_saved_years': round((base_months - over_months) / 12.0, 1),
            'interest_saved': round(base_interest - over_interest, 2),
            'ltv_pct': round(ltv, 2) if ltv != "N/A" else "N/A",
            'baseline_interest': round(base_interest, 2),
            'overpay_interest': round(over_interest, 2),
            'baseline_months': base_months,
            'overpay_months': over_months
        }
        
        return {
            'structured_summary': structured_summary,
            'chart_data': _generate_chart_data(base_hist, over_hist, p['principal']),
            'yearly_schedule': _generate_yearly_schedule_from_capitalized(over_hist, p['principal']),
            'monthly_schedule': _normalize_monthly_history(over_hist)
        }

    def calculate_rollover_summary(self, data: Dict[str, Any]) -> Dict[str, Any]:
        # (This function is unchanged)
        eur_inputs = self._parse_mortgage_data(data.get('eur_data', {}))
        gbp_inputs = self._parse_mortgage_data(data.get('gbp_data', {}))
        rate = float(data.get('conversion_rate', 0.85))

        if eur_inputs['principal'] <= 0 or gbp_inputs['principal'] <= 0:
            return {'error': 'EUR or GBP mortgage data is missing or invalid.'}

        eur_inputs.pop('propval', None); eur_inputs.pop('inflation', None)
        gbp_inputs.pop('propval', None); gbp_inputs.pop('inflation', None)

        eur_base_hist, _ = self._amortize_flexible(
            principal=eur_inputs['principal'], annual_rate_pct=eur_inputs['annual_rate_pct'], years=eur_inputs['years'],
            rate_changes=eur_inputs.get('rate_changes')
        )
        eur_over_hist, eur_first_payment = self._amortize_flexible(**eur_inputs)
        
        eur_months = len(eur_over_hist)
        eur_years = round(eur_months / 12.0, 1)
        eur_interest_baseline = sum(h["Interest"] for h in eur_base_hist)
        eur_interest_with_overpay = sum(h["Interest"] for h in eur_over_hist)

        freed_eur = eur_first_payment + eur_inputs.get('monthly_overpay', 0.0) + (eur_first_payment * (eur_inputs.get('overpay_pct_of_base', 0.0) / 100.0))
        freed_gbp = freed_eur * rate

        uk_over_hist, _ = self._amortize_flexible(**gbp_inputs)
        
        uk_baseline_years = round(len(uk_over_hist) / 12.0, 1)
        uk_baseline_interest_total = sum(h["Interest"] for h in uk_over_hist)
        uk_baseline_months = len(uk_over_hist)

        if eur_months >= uk_baseline_months:
            return {'error': 'No rollover benefit...'}

        uk_balance_at_roll = uk_over_hist[eur_months - 1]["Balance"]
        uk_interest_pre_roll = sum(h["Interest"] for h in uk_over_hist[:eur_months])
        
        years_left_baseline = (uk_baseline_months - eur_months) / 12.0
        months_left_baseline = uk_baseline_months - eur_months

        post_roll_inputs = gbp_inputs.copy()
        post_roll_inputs['principal'] = uk_balance_at_roll
        post_roll_inputs['years'] = years_left_baseline
        post_roll_inputs['monthly_overpay'] += freed_gbp
        if post_roll_inputs['one_off_lump_month'] <= eur_months:
            post_roll_inputs['one_off_lump'] = 0.0
            
        new_rate_changes = {}
        for month, new_rate in gbp_inputs.get('rate_changes', {}).items():
            if month > eur_months:
                new_rate_changes[month - eur_months] = new_rate
        post_roll_inputs['rate_changes'] = new_rate_changes

        uk_post_roll_hist, _ = self._amortize_flexible(**post_roll_inputs)
        
        uk_post_roll_months = len(uk_post_roll_hist)
        uk_post_roll_years = round(uk_post_roll_months / 12.0, 1)
        uk_interest_post_roll = sum(h["Interest"] for h in uk_post_roll_hist)
        
        uk_with_roll_interest_total = uk_interest_pre_roll + uk_interest_post_roll
        uk_interest_saved_vs_baseline = uk_baseline_interest_total - uk_with_roll_interest_total
        annual_overpay_pct = round((freed_gbp * 12.0 / uk_balance_at_roll) * 100.0, 1) if uk_balance_at_roll > 0 else 0.0
        time_saved = round(uk_baseline_years - uk_post_roll_years, 1)
        total_free_time = round(eur_years + uk_post_roll_years, 1)

        return {
            "eur_payoff_time_years": eur_years, "eur_payoff_time_months": eur_months,
            "eur_freed_payment": round(freed_eur, 2), "gbp_freed_payment": round(freed_gbp, 2),
            "conversion_rate": rate, "eur_baseline_interest": round(eur_interest_baseline, 2),
            "eur_overpay_interest": round(eur_interest_with_overpay, 2),
            "eur_interest_saved": round(eur_interest_baseline - eur_interest_with_overpay, 2),
            "uk_baseline_payoff_years": uk_baseline_years,
            "uk_remaining_term_at_payoff_years": round(years_left_baseline, 1),
            "uk_remaining_term_at_payoff_months": months_left_baseline,
            "uk_baseline_total_interest": round(uk_baseline_interest_total, 2),
            "uk_balance_at_rollover": round(uk_balance_at_roll, 2),
            "uk_extra_monthly_from_eur": round(freed_gbp, 2),
            "uk_annual_overpay_pct": annual_overpay_pct,
            "uk_payoff_after_rollover_years": uk_post_roll_years,
            "uk_total_interest_with_rollover": round(uk_with_roll_interest_total, 2),
            "uk_interest_saved_vs_baseline": round(uk_interest_saved_vs_baseline, 2),
            "comparison_baseline_years": uk_baseline_years,
            "comparison_with_rollover_years": uk_post_roll_years,
            "comparison_time_saved_years": time_saved,
            "total_mortgage_free_time_years": total_free_time
        }

    def calculate_refinance_summary(self, data: Dict[str, Any]) -> Dict[str, Any]:
        # (This function is unchanged)
        try:
            curr = data.get('current', {})
            ref = data.get('refinance', {})
            curr_parsed = self._parse_mortgage_data(curr)
            
            sim_inputs = {
                "principal": curr_parsed['principal'], "annual_rate_pct": curr_parsed['annual_rate_pct'],
                "years": curr_parsed['years'], "monthly_overpay": curr_parsed.get('monthly_overpay', 0.0),
                "overpay_pct_of_base": curr_parsed.get('overpay_pct_of_base', 0.0),
                "annual_lump": curr_parsed.get('annual_lump', 0.0),
                "annual_lump_month": curr_parsed.get('annual_lump_month', 12),
                "one_off_lump": curr_parsed.get('one_off_lump', 0.0),
                "one_off_lump_month": curr_parsed.get('one_off_lump_month', 0),
                "rate_changes": curr_parsed.get('rate_changes', {})
            }
            base_hist, _ = self._amortize_flexible(**sim_inputs)

            months_elapsed = int(data.get('months_elapsed', 0))
            outstanding = base_hist[months_elapsed - 1]['Balance'] if months_elapsed > 0 and months_elapsed <= len(base_hist) else curr_parsed['principal']
            fees = float(ref.get('fees', 0.0)) + float(ref.get('closing_costs', 0.0))
            ref_principal = float(ref.get('loan', outstanding))
            ref_parsed_rate = _normalize_rate_input(ref.get('rate', 0.0))
            ref_years = int(ref.get('years', curr_parsed['years']))

            ref_sim_inputs = {
                "principal": ref_principal, "annual_rate_pct": ref_parsed_rate, "years": ref_years,
                "monthly_overpay": float(ref.get('monthly_overpay', 0.0)),
                "overpay_pct_of_base": float(ref.get('overpay_pct_of_base', 0.0)),
                "annual_lump": float(ref.get('annual_lump', 0.0)),
                "annual_lump_month": int(ref.get('annual_lump_month', 12)),
                "one_off_lump": float(ref.get('one_off_lump', 0.0)),
                "one_off_lump_month": int(ref.get('one_off_lump_month', 0)),
                "rate_changes": _parse_rate_changes(ref.get('rate_changes', ''))
            }
            ref_hist, _ = self._amortize_flexible(**ref_sim_inputs)

            def cum_interest(hist):
                cum = []; s = 0.0
                for row in hist:
                    s += float(row.get('Interest', 0.0)); cum.append(round(s, 2))
                return cum

            base_cum = cum_interest(base_hist)
            ref_cum_with_fees = [round(x + fees, 2) for x in cum_interest(ref_hist)]

            break_even = None
            max_len = min(len(base_cum), len(ref_cum_with_fees))
            for i in range(max_len):
                if ref_cum_with_fees[i] < base_cum[i]:
                    break_even = i + 1; break

            base_total_interest = sum(r['Interest'] for r in base_hist)
            ref_total_interest = sum(r['Interest'] for r in ref_hist) + fees

            return {
                'baseline_monthly': _normalize_monthly_history(base_hist),
                'refinance_monthly': _normalize_monthly_history(ref_hist),
                'break_even_month': break_even, 'fees': round(fees, 2),
                'baseline_total_interest': round(base_total_interest, 2),
                'refinance_total_interest': round(ref_total_interest, 2),
                'interest_saved': round(base_total_interest - (ref_total_interest - fees), 2)
            }
        except Exception as e:
            return {'error': f'Refinance calculation error: {str(e)}'}

    def run_calculator(self, data: Dict[str, Any]) -> Dict[str, Any]:
        # (This function is unchanged)
        try:
            p = float(data.get('loan_amount', 0.0))
            r_pct = _normalize_rate_input(data.get('annual_rate', 0.0))
            y_curr = int(data.get('current_years', 0))
            y_targ = int(data.get('target_years', 0))
            
            if p <= 0 or y_curr <= 0 or y_targ <= 0: return {'error': 'Invalid inputs.'}
            if y_targ >= y_curr: return {'error': 'Target years must be less than current years.'}

            r_m = (r_pct / 100.0) / 12.0
            base_monthly = _base_payment_for(p, r_m, y_curr * 12)
            target_monthly = _base_payment_for(p, r_m, y_targ * 12)
            
            req_overpay = max(0.0, target_monthly - base_monthly)
            annual_overpay = req_overpay * 12.0
            percent_of_loan = (annual_overpay / p * 100.0) if p > 0 else 0.0
            
            sim_hist, _ = self._amortize_flexible(
                principal=p, annual_rate_pct=r_pct, years=y_curr,
                monthly_overpay=req_overpay
            )
            
            return {
                'structured_summary': {
                    'base_monthly': round(base_monthly, 2),
                    'target_monthly': round(target_monthly, 2),
                    'required_overpayment': round(req_overpay, 2),
                    'annual_overpayment': round(annual_overpay, 2),
                    'percent_of_loan': round(percent_of_loan, 2),
                    'cap_status': "Within 10% cap" if percent_of_loan <= 10.0 else "Exceeds 10% cap"
                },
                'yearly_schedule': _generate_yearly_schedule_from_capitalized(sim_hist, p),
                'monthly_schedule': _normalize_monthly_history(sim_hist),
                'chart_data': _generate_chart_data([], sim_hist, p)
            }
        except Exception as e:
            return {'error': f'Calculation error: {str(e)}'}

    # -----------------------
    # CREDIT CARD PAYOFF
    # -----------------------
    def _calculate_revolving_payoff(self, balance, apr, min_payment_pct, min_payment_flat, fixed_payment):
        """Helper to run a single credit card payoff simulation."""
        bal = float(balance)
        r_m = float(apr) / 100.0 / 12.0
        
        history = []
        month = 0
        total_interest = 0.0
        
        # Limit to 50 years (600 months) to prevent infinite loops
        while bal > 0 and month < 600:
            month += 1
            interest = bal * r_m
            total_interest += interest
            
            # Determine payment
            if fixed_payment > 0:
                payment = fixed_payment
            else:
                # Calculate minimum payment
                min_pct = bal * (float(min_payment_pct) / 100.0)
                payment = max(min_pct, float(min_payment_flat))
                
            # Ensure payment covers at least the interest (if not, it's a debt spiral)
            if payment < interest and fixed_payment <= 0:
                payment = interest + 1 # Pay at least £1 principle
                if month > 12: # If it's still not working after a year, break
                     # This is a debt spiral, cap it
                     return history, total_interest, -1 # -1 indicates debt spiral
            
            principal_paid = payment - interest
            
            # Final payment
            if (bal + interest) < payment:
                payment = bal + interest
                principal_paid = bal
                bal = 0.0
            else:
                bal -= principal_paid
                
            history.append({
                "Month": month,
                "Payment": round(payment, 2),
                "Principal": round(principal_paid, 2),
                "Interest": round(interest, 2),
                "Balance": round(bal, 2)
            })
            
        return history, total_interest, month

    def calculate_revolving_debt(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculates payoff for revolving credit (credit cards).
        Compares minimum payment vs. a fixed payment.
        """
        try:
            balance = float(data.get('balance', 0.0))
            apr = _normalize_rate_input(data.get('apr', 0.0))
            min_pct = float(data.get('min_payment_pct', 2.0))
            min_flat = float(data.get('min_payment_flat', 25.0))
            fixed_payment = float(data.get('fixed_payment', 0.0))
            
            if balance <= 0 or apr <= 0:
                return {'error': 'Please enter a valid balance and APR.'}

            # 1. Minimum Payment Simulation
            min_hist, min_interest, min_months = self._calculate_revolving_payoff(
                balance, apr, min_pct, min_flat, 0
            )
            
            # 2. Fixed Payment Simulation
            if fixed_payment > 0:
                # Check if fixed payment is high enough
                first_interest = balance * (apr / 100.0 / 12.0)
                if fixed_payment <= first_interest:
                    return {
                        'error': f'Your fixed payment (£{fixed_payment:,.2f}) must be higher than the first month\'s interest (£{first_interest:,.2f}) to pay off the debt.'
                    }
                
                fixed_hist, fixed_interest, fixed_months = self._calculate_revolving_payoff(
                    balance, apr, 0, 0, fixed_payment
                )
            else:
                fixed_hist, fixed_interest, fixed_months = [], 0.0, 0

            # 3. Format results
            return {
                'structured_summary': {
                    'min_pay_months': min_months,
                    'min_pay_interest': round(min_interest, 2),
                    'fixed_pay_months': fixed_months,
                    'fixed_pay_interest': round(fixed_interest, 2),
                    'interest_saved': round(min_interest - fixed_interest, 2) if fixed_payment > 0 else 0.0,
                    'time_saved_years': round((min_months - fixed_months) / 12.0, 1) if fixed_payment > 0 else 0.0
                },
                # We can reuse the same chart/table models
                'chart_data': _generate_chart_data(min_hist, fixed_hist, balance),
                'yearly_schedule': _generate_yearly_schedule_from_capitalized(fixed_hist, balance),
                'monthly_schedule': _normalize_monthly_history(fixed_hist)
            }
            
        except Exception as e:
            return {'error': f'Credit card calculation error: {str(e)}'}

    # -----------------------
    # SAVINGS GROWTH CALC
    # -----------------------
    def calculate_savings_growth(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculates compounded savings growth with periodic contributions.
        """
        try:
            balance = float(data.get('initial_balance', 0.0))
            contribution = float(data.get('contribution_amount', 0.0))
            annual_rate = float(data.get('annual_rate', 0.0))
            years = int(data.get('years', 0))
            frequency = data.get('frequency', 'monthly').lower()
            
            if years <= 0:
                return {'error': 'Projection years must be greater than zero.'}

            periods = years * 12
            r_annual = annual_rate / 100.0
            r_monthly = r_annual / 12.0
            
            history: List[Dict[str, Any]] = []

            for month in range(1, periods + 1):
                # 1. Apply Contribution based on frequency
                if frequency == 'monthly':
                    balance += contribution
                elif frequency == 'weekly':
                    # 4.3333 weeks per month
                    balance += contribution * (4.33333) 
                
                # 2. Apply Interest
                interest = balance * r_monthly
                balance += interest
                
                history.append({
                    "period": month,
                    "balance": round(balance, 2)
                })
            
            return {
                'final_balance': round(balance, 2),
                'history': history
            }
            
        except Exception as e:
            return {'error': f'Savings growth calculation error: {str(e)}'}

# -----------------------
# Excel Exporter (Fix for "not defined" error)
# -----------------------
def _export_rollover_to_excel_bytes(rollover_result: Dict[str, Any]) -> Tuple[bytes, str]:
    """FIX: Moved this function definition outside the AmortizationEngine class 
           but before the router, where it is called."""
    eur_base = rollover_result.get('eur_baseline_monthly', [])
    eur_over = rollover_result.get('eur_monthly', [])
    uk_base = rollover_result.get('uk_baseline_monthly', [])
    uk_post = rollover_result.get('uk_post_roll_monthly', [])
    chart_data = rollover_result.get('chart_data', [])
    df_eur_base = pd.DataFrame(eur_base); df_eur_over = pd.DataFrame(eur_over)
    df_uk_base = pd.DataFrame(uk_base); df_uk_post = pd.DataFrame(uk_post)
    df_chart = pd.DataFrame(chart_data)
    df_eur_base_yearly = pd.DataFrame(_generate_yearly_schedule_from_normalized(eur_base)) if eur_base else pd.DataFrame()
    df_eur_over_yearly = pd.DataFrame(_generate_yearly_schedule_from_normalized(eur_over)) if eur_over else pd.DataFrame()
    df_uk_base_yearly = pd.DataFrame(_generate_yearly_schedule_from_normalized(uk_base)) if uk_base else pd.DataFrame()
    df_uk_post_yearly = pd.DataFrame(_generate_yearly_schedule_from_normalized(uk_post)) if uk_post else pd.DataFrame()
    max_month = 0
    for lst in (eur_base, eur_over, uk_base, uk_post):
        if lst: max_month = max(max_month, max(int(x.get('month', 0)) for x in lst))
    comp_rows = []
    for m in range(1, max_month + 1):
        def find_balance(lst):
            if not lst: return None
            for x in lst:
                if int(x.get('month', x.get('Month', 0))) == m: return float(x.get('balance', x.get('Balance', 0.0)))
            return None
        comp_rows.append({
            'month': m, 'eur_baseline_balance': find_balance(eur_base),
            'eur_overpay_balance': find_balance(eur_over),
            'uk_baseline_balance': find_balance(uk_base),
            'uk_post_roll_balance': find_balance(uk_post)
        })
    df_comp = pd.DataFrame(comp_rows)
    summary_keys = [
        'eur_payoff_time_years','eur_payoff_time_months','eur_freed_payment','gbp_freed_payment',
        'conversion_rate','eur_baseline_interest','eur_overpay_interest','eur_interest_saved',
        'uk_baseline_payoff_years','uk_remaining_term_at_payoff_years','uk_balance_at_rollover',
        'uk_extra_monthly_from_eur','uk_total_interest_with_rollover','uk_interest_saved_vs_baseline',
        'total_mortgage_free_time_years'
    ]
    summary_rows = [{'metric': k, 'value': rollover_result[k]} for k in summary_keys if k in rollover_result]
    df_summary = pd.DataFrame(summary_rows)
    buffer = io.BytesIO()
    with pd.ExcelWriter(buffer, engine='xlsxwriter') as writer:
        df_eur_base.to_excel(writer, sheet_name='EUR_Baseline_Monthly', index=False)
        df_eur_over.to_excel(writer, sheet_name='EUR_Overpay_Monthly', index=False)
        df_eur_base_yearly.to_excel(writer, sheet_name='EUR_Baseline_Yearly', index=False)
        df_eur_over_yearly.to_excel(writer, sheet_name='EUR_Overpay_Yearly', index=False)
        df_uk_base.to_excel(writer, sheet_name='UK_Baseline_Monthly', index=False)
        df_uk_post.to_excel(writer, sheet_name='UK_PostRoll_Monthly', index=False)
        df_uk_base_yearly.to_excel(writer, sheet_name='UK_Baseline_Yearly', index=False)
        df_uk_post_yearly.to_excel(writer, sheet_name='UK_PostRoll_Yearly', index=False)
        df_comp.to_excel(writer, sheet_name='Comparison', index=False)
        df_chart.to_excel(writer, sheet_name='Chart_Data', index=False)
        df_summary.to_excel(writer, sheet_name='Summary', index=False)
        workbook = writer.book
        header_fmt = workbook.add_format({'bold': True, 'bg_color': '#DCE6F1', 'border':1})
        currency_fmt = workbook.add_format({'num_format': '£#,##0.00', 'border':1})
        int_fmt = workbook.add_format({'num_format': '0', 'border':1})
        default_fmt = workbook.add_format({'border':1})
        def format_sheet(sheet_name, df):
            worksheet = writer.sheets[sheet_name]
            worksheet.set_row(0, None, header_fmt)
            if df.empty: return
            for i, col in enumerate(df.columns):
                width = max(12, min(40, len(str(col)) + 2))
                if any(x in str(col).lower() for x in ('balance','payment','principal','interest','fees','amount','total')):
                    worksheet.set_column(i, i, width, currency_fmt)
                elif 'month' in str(col).lower() or 'year' in str(col).lower():
                    worksheet.set_column(i, i, width, int_fmt)
                else:
                    worksheet.set_column(i, i, width, default_fmt)
        sheets_and_dfs = {
            'EUR_Baseline_Monthly': df_eur_base, 'EUR_Overpay_Monthly': df_eur_over,
            'EUR_Baseline_Yearly': df_eur_base_yearly, 'EUR_Overpay_Yearly': df_eur_over_yearly,
            'UK_Baseline_Monthly': df_uk_base, 'UK_PostRoll_Monthly': df_uk_post,
            'UK_Baseline_Yearly': df_uk_base_yearly, 'UK_PostRoll_Yearly': df_uk_post_yearly,
            'Comparison': df_comp, 'Chart_Data': df_chart, 'Summary': df_summary
        }
        for sn, df in sheets_and_dfs.items():
            format_sheet(sn, df)
        if not df_chart.empty and 'month' in df_chart.columns:
            worksheet_chart = writer.sheets['Chart_Data']
            rows = len(df_chart)
            chart = workbook.add_chart({'type': 'line'})
            def col_index(dfcols, name):
                try: return dfcols.get_loc(name)
                except Exception: return None
            idx_baseline = col_index(df_chart.columns, 'baseline_balance')
            if idx_baseline is not None:
                chart.add_series({
                    'name': 'EUR Baseline', 'categories': ['Chart_Data', 1, 0, rows, 0],
                    'values': ['Chart_Data', 1, idx_baseline, rows, idx_baseline], 'line': {'color': '#4472C4'}
                })
            idx_overpay = col_index(df_chart.columns, 'overpay_balance')
            if idx_overpay is not None:
                chart.add_series({
                    'name': 'EUR Overpay', 'categories': ['Chart_Data', 1, 0, rows, 0],
                    'values': ['Chart_Data', 1, idx_overpay, rows, idx_overpay], 'line': {'color': '#ED7D31'}
                })
            idx_uk_base = col_index(df_chart.columns, 'uk_baseline_balance')
            if idx_uk_base is not None:
                chart.add_series({
                    'name': 'UK Baseline', 'categories': ['Chart_Data', 1, 0, rows, 0],
                    'values': ['Chart_Data', 1, idx_uk_base, rows, idx_uk_base], 'line': {'color': '#70AD47'}
                })
            idx_uk_post = col_index(df_chart.columns, 'uk_post_roll_balance')
            if idx_uk_post is not None:
                chart.add_series({
                    'name': 'UK Post-Roll', 'categories': ['Chart_Data', 1, 0, rows, 0],
                    'values': ['Chart_Data', 1, idx_uk_post, rows, idx_uk_post], 'line': {'color': '#FFC000'}
                })
            chart.set_title({'name': 'Balances over time (sampled)'})
            chart.set_x_axis({'name': 'Month'}); chart.set_y_axis({'name': 'Balance'})
            worksheet_chart.insert_chart(rows + 3, 0, chart, {'x_scale': 1.6, 'y_scale': 1.2})
    buffer.seek(0)
    return buffer.read(), "rollover_analysis.xlsx"


# -----------------------
# Router
# -----------------------

def process_request(script: str, data: Dict[str, Any]) -> str:
    """
    Robust router for integration. Accepts a script name (free text) and a data dict.
    Returns a JSON string.
    """
    engine = AmortizationEngine()
    result: Dict[str, Any] = {}

    try:
        script_raw = script or ""
        script_lower = " ".join(script_raw.lower().split())

        # Debug logging to server console
        print("=" * 60)
        print(f"PROCESS_REQUEST: script_raw = '{script_raw}'")
        print(f"PROCESS_REQUEST: script_normalized = '{script_lower}'")
        print(f"PROCESS_REQUEST: data keys = {list(data.keys()) if isinstance(data, dict) else type(data)}")
        print("=" * 60)

        # --- SAVINGS GROWTH ROUTE ---
        if "savings growth" in script_lower or "future value" in script_lower:
            result = engine.calculate_savings_growth(data)
        # ----------------------------
        
        elif "export" in script_lower and "rollover" in script_lower:
            res = engine.calculate_rollover_summary(data)
            if 'error' in res: result = res
            else:
                # FIX: Function is now correctly defined above
                excel_bytes, filename = _export_rollover_to_excel_bytes(res) 
                result = {'excel_base64': base64.b64encode(excel_bytes).decode('ascii'), 'filename': filename}
        
        elif "rollover" in script_lower:
            result = engine.calculate_rollover_summary(data)
        
        elif "refinance" in script_lower:
            result = engine.calculate_refinance_summary(data)
        
        elif "credit card" in script_lower or "revolving" in script_lower:
            result = engine.calculate_revolving_debt(data)
            
        elif any(k in script_lower for k in ("calculator", "required overpayment", "run_calculator", "target",
                                             "overpayment calculator", "overpayment simulation", "overpayment simulation logic")):
            result = engine.run_calculator(data)
            
        elif any(k in script_lower for k in ("mortgage simulation", "eu mortgage", "uk mortgage", "overpayment summary", "overpayment", "other loan")):
            result = engine.calculate_overpayment_summary(data)
            
        elif "mortgage" in script_lower:
            result = engine.calculate_overpayment_summary(data)
            
        else:
            result = {"error": "Unknown script name.", "received_script": script_raw, "normalized_script": script_lower}

    except Exception as e:
        result = {"error": f"Python engine error: {str(e)}", "received_script": script, "received_data": data}

    return json.dumps(result)