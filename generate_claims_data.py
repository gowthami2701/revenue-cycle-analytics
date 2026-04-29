"""
Revenue Cycle Analytics - Synthetic Claims Data Generator
Generates realistic healthcare claims data for portfolio demonstration
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import csv
import os

# Seed for reproducibility
np.random.seed(42)
random.seed(42)

# ── REFERENCE DATA ─────────────────────────────────────────────────────────────

PAYERS = {
    'Medicare FFS':     {'weight': 0.35, 'denial_rate': 0.08, 'avg_payment': 0.82},
    'Medicaid MCO':     {'weight': 0.20, 'denial_rate': 0.31, 'avg_payment': 0.61},
    'Blue Cross PPO':   {'weight': 0.18, 'denial_rate': 0.11, 'avg_payment': 0.78},
    'Aetna HMO':        {'weight': 0.12, 'denial_rate': 0.14, 'avg_payment': 0.75},
    'UnitedHealth':     {'weight': 0.10, 'denial_rate': 0.13, 'avg_payment': 0.76},
    'Self-Pay':         {'weight': 0.05, 'denial_rate': 0.45, 'avg_payment': 0.22},
}

CPT_CODES = {
    '99213': {'desc': 'Office Visit - Established - Low',    'charge': 185,  'denial_mult': 3.1},
    '99214': {'desc': 'Office Visit - Established - Mod',    'charge': 250,  'denial_mult': 3.4},
    '99215': {'desc': 'Office Visit - Established - High',   'charge': 340,  'denial_mult': 2.8},
    '93000': {'desc': 'Electrocardiogram',                   'charge': 95,   'denial_mult': 1.2},
    '71046': {'desc': 'Chest X-Ray 2 Views',                 'charge': 220,  'denial_mult': 1.1},
    '85025': {'desc': 'Complete Blood Count',                'charge': 85,   'denial_mult': 0.9},
    '36415': {'desc': 'Routine Venipuncture',                'charge': 45,   'denial_mult': 0.7},
    '99232': {'desc': 'Subsequent Hospital Care',            'charge': 420,  'denial_mult': 1.8},
    '27447': {'desc': 'Total Knee Replacement',              'charge': 18500,'denial_mult': 2.2},
    '43239': {'desc': 'Upper GI Endoscopy w/ Biopsy',        'charge': 2800, 'denial_mult': 1.6},
}

DENIAL_REASONS = {
    'CO-50':  {'desc': 'Medical Necessity Not Established',      'weight': 0.34},
    'CO-97':  {'desc': 'Service Already Adjudicated',            'weight': 0.18},
    'CO-4':   {'desc': 'Service Not Covered by Plan',            'weight': 0.15},
    'CO-16':  {'desc': 'Claim Lacks Information',                'weight': 0.12},
    'CO-109': {'desc': 'Claim Not Covered by Payer',             'weight': 0.09},
    'CO-29':  {'desc': 'Time Limit Expired',                     'weight': 0.07},
    'CO-22':  {'desc': 'Coordination of Benefits',               'weight': 0.05},
}

PROVIDERS = [
    'Dr. Sarah Johnson, MD',   'Dr. Michael Chen, MD',    'Dr. Priya Patel, MD',
    'Dr. Robert Williams, MD', 'Dr. Lisa Anderson, NP',   'Dr. James Martinez, MD',
    'Dr. Emily Thompson, PA',  'Dr. David Kim, MD',
]

DEPARTMENTS = ['Internal Medicine', 'Cardiology', 'Orthopedics', 'Emergency', 
               'Radiology', 'Laboratory', 'Surgery', 'Primary Care']

ICD10_CODES = {
    'E11.9':  'Type 2 Diabetes without complications',
    'I10':    'Essential Hypertension',
    'J18.9':  'Pneumonia, unspecified',
    'M17.11': 'Primary osteoarthritis, right knee',
    'K21.0':  'GERD with esophagitis',
    'Z00.00': 'Encounter for general adult medical examination',
    'I25.10': 'Atherosclerotic heart disease',
    'F32.9':  'Major depressive disorder',
}


def generate_claims(n_claims: int = 5000) -> pd.DataFrame:
    """Generate realistic healthcare claims dataset."""
    
    print(f"Generating {n_claims} synthetic healthcare claims...")
    
    payer_names = list(PAYERS.keys())
    payer_weights = [PAYERS[p]['weight'] for p in payer_names]
    cpt_list = list(CPT_CODES.keys())
    icd_list = list(ICD10_CODES.keys())
    denial_codes = list(DENIAL_REASONS.keys())
    denial_weights = [DENIAL_REASONS[d]['weight'] for d in denial_codes]
    
    records = []
    start_date = datetime(2023, 1, 1)
    
    for i in range(n_claims):
        # Base claim info
        claim_id = f"CLM{str(i+1).zfill(6)}"
        service_date = start_date + timedelta(days=random.randint(0, 364))
        submit_date = service_date + timedelta(days=random.randint(1, 14))
        
        payer = random.choices(payer_names, weights=payer_weights)[0]
        payer_info = PAYERS[payer]
        
        cpt = random.choice(cpt_list)
        cpt_info = CPT_CODES[cpt]
        icd10 = random.choice(icd_list)
        provider = random.choice(PROVIDERS)
        department = random.choice(DEPARTMENTS)
        
        # Charge amount with some variance
        charge = cpt_info['charge'] * np.random.uniform(0.85, 1.15)
        
        # Determine claim status
        effective_denial_rate = payer_info['denial_rate'] * cpt_info['denial_mult']
        effective_denial_rate = min(effective_denial_rate, 0.75)
        
        is_denied = random.random() < effective_denial_rate
        
        if is_denied:
            status = 'Denied'
            denial_code = random.choices(denial_codes, weights=denial_weights)[0]
            denial_desc = DENIAL_REASONS[denial_code]['desc']
            payment = 0
            payment_date = None
            # Some denials get appealed and paid
            appealed = random.random() < 0.45
            if appealed:
                status = 'Appealed - Paid'
                payment = charge * payer_info['avg_payment'] * np.random.uniform(0.9, 1.0)
                payment_date = submit_date + timedelta(days=random.randint(30, 90))
        else:
            denial_code = None
            denial_desc = None
            appealed = False
            if random.random() < 0.05:
                status = 'Pending'
                payment = 0
                payment_date = None
            else:
                status = 'Paid'
                payment = charge * payer_info['avg_payment'] * np.random.uniform(0.88, 1.02)
                payment_date = submit_date + timedelta(days=random.randint(14, 45))
        
        # Days in AR calculation
        if payment_date:
            days_in_ar = (payment_date - submit_date).days
        elif status == 'Pending':
            days_in_ar = (datetime(2024, 1, 1) - submit_date).days
        else:
            days_in_ar = (datetime(2024, 1, 1) - submit_date).days
        
        records.append({
            'claim_id':         claim_id,
            'patient_id':       f"PT{random.randint(10000, 99999)}",
            'service_date':     service_date.strftime('%Y-%m-%d'),
            'submit_date':      submit_date.strftime('%Y-%m-%d'),
            'payment_date':     payment_date.strftime('%Y-%m-%d') if payment_date else None,
            'provider':         provider,
            'department':       department,
            'payer':            payer,
            'cpt_code':         cpt,
            'cpt_description':  cpt_info['desc'],
            'icd10_primary':    icd10,
            'icd10_description':ICD10_CODES[icd10],
            'charge_amount':    round(charge, 2),
            'payment_amount':   round(payment, 2),
            'adjustment_amount':round(charge - payment, 2),
            'status':           status,
            'denial_code':      denial_code,
            'denial_reason':    denial_desc,
            'was_appealed':     appealed,
            'days_in_ar':       days_in_ar,
            'service_month':    service_date.strftime('%Y-%m'),
        })
    
    df = pd.DataFrame(records)
    print(f"✅ Generated {len(df)} claims")
    print(f"   Overall Denial Rate: {(df['status']=='Denied').mean():.1%}")
    print(f"   Avg Days in AR: {df[df['days_in_ar']>0]['days_in_ar'].mean():.1f}")
    print(f"   Total Charges: ${df['charge_amount'].sum():,.0f}")
    print(f"   Total Payments: ${df['payment_amount'].sum():,.0f}")
    print(f"   Net Collection Rate: {df['payment_amount'].sum()/df['charge_amount'].sum():.1%}")
    
    return df


def calculate_kpis(df: pd.DataFrame) -> dict:
    """Calculate core Revenue Cycle KPIs."""
    
    total_claims = len(df)
    denied = (df['status'] == 'Denied').sum()
    paid_first_pass = ((df['status'] == 'Paid') & (~df['was_appealed'])).sum()
    
    kpis = {
        'Total Claims':             total_claims,
        'Total Charges':            f"${df['charge_amount'].sum():,.0f}",
        'Total Payments':           f"${df['payment_amount'].sum():,.0f}",
        'Denial Rate':              f"{denied/total_claims:.1%}",
        'Clean Claim Rate':         f"{(total_claims-denied)/total_claims:.1%}",
        'First Pass Resolution':    f"{paid_first_pass/total_claims:.1%}",
        'Avg Days in AR':           f"{df[df['days_in_ar']>0]['days_in_ar'].mean():.1f} days",
        'Net Collection Rate':      f"{df['payment_amount'].sum()/df['charge_amount'].sum():.1%}",
    }
    
    return kpis


if __name__ == '__main__':
    os.makedirs('data', exist_ok=True)
    
    # Generate dataset
    df = generate_claims(5000)
    df.to_csv('data/claims_data.csv', index=False)
    print(f"\n💾 Saved to data/claims_data.csv")
    
    # Print KPIs
    print("\n📊 KEY PERFORMANCE INDICATORS")
    print("=" * 40)
    kpis = calculate_kpis(df)
    for k, v in kpis.items():
        print(f"  {k:<30} {v}")
    
    # Denial breakdown
    print("\n🚫 TOP DENIAL REASONS")
    print("=" * 40)
    denials = df[df['denial_code'].notna()]
    denial_summary = denials.groupby(['denial_code', 'denial_reason']).agg(
        Count=('claim_id', 'count'),
        Total_Charges=('charge_amount', 'sum')
    ).sort_values('Count', ascending=False)
    print(denial_summary.to_string())
    
    # Payer performance
    print("\n💰 PAYER PERFORMANCE")
    print("=" * 40)
    payer_perf = df.groupby('payer').agg(
        Claims=('claim_id', 'count'),
        Denial_Rate=('status', lambda x: (x=='Denied').mean()),
        Avg_Days_AR=('days_in_ar', 'mean'),
        Total_Payments=('payment_amount', 'sum')
    ).round(3)
    print(payer_perf.to_string())
