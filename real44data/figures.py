"""Render real44 bounds and runtime figures from validated outputs."""
from pathlib import Path
import argparse
import csv
import json
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    output = parser.parse_args().output.resolve()
    assert json.loads((output/'validation.json').read_text())['passed']
    assert output != Path(__file__).resolve().parent/'reference'
    rows = list(csv.DictReader((output/'cutoff_results.csv').open()))
    times = list(csv.DictReader((output/'timing_summary.csv').open()))
    dest = output/'figures'
    dest.mkdir(exist_ok=True)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'pdf.fonttype':42,'axes.spines.top':False,'axes.spines.right':False})
    selected = [r for r in rows if r['full_support']=='True' and 1.5<=float(r['tau2'])<=5]
    fig,ax = plt.subplots(figsize=(5,3),layout='constrained')
    for method,color,label in [('single','#333333','Singleton'),('pair','#0072B2','Pairwise')]:
        ax.plot([float(r['tau2']) for r in selected],[float(r[method+'_max_bound']) for r in selected],color=color,label=label)
    ax.axhline(1,color='black',ls='--',lw=.8)
    ax.axvspan(3.30,4.05,color='#56B4E9',alpha=.15)
    ax.set(xlabel=r'Cutoff $\tau^2$',ylabel='Maximum bound over k',xlim=(1.5,5))
    ax.legend(frameon=False)
    for ext in ['png','pdf','svg']:
        fig.savefig(dest/f'cutoff_bounds.{ext}',dpi=240)
    plt.close(fig)
    cutoffs = [2.,2.5,3.,3.5,4.,4.5,5.,8.,16.]
    lookup = {(float(r['tau2']),r['method']):r for r in times}
    fig,ax = plt.subplots(figsize=(8.5,3.3),layout='constrained')
    for j,(method,color,label) in enumerate([('single','#777777','Singleton'),('pair','#0072B2','Pairwise'),('cascade','#009E73','Cascade')]):
        records = [lookup[t,method] for t in cutoffs]
        median = np.array([float(r['total_median_ms']) for r in records])
        error = [median-[float(r['total_p25_ms']) for r in records],[float(r['total_p75_ms']) for r in records]-median]
        ax.bar(np.arange(len(cutoffs))+(j-1)*.25,median,width=.24,color=color,label=label,yerr=error,capsize=2)
    ax.set_xticks(range(len(cutoffs)),[f'{t:g}' for t in cutoffs])
    ax.set(xlabel=r'Cutoff $\tau^2$',ylabel='Time (ms; median and IQR of 9 calls)')
    ax.legend(frameon=False,ncol=3)
    for ext in ['png','pdf','svg']:
        fig.savefig(dest/f'cutoff_timing.{ext}',dpi=220)
    plt.close(fig)
    print(f'Saved figures in {dest}')


if __name__ == '__main__':
    main()
