"""Independently reconstruct the real44 certificate and check paper decisions."""
from pathlib import Path
import argparse
import csv
import json
import math
import numpy as np
import toml
from scipy.spatial.transform import Rotation
from prepare import ROOT, digest, verify


def pose(rotation, translation):
    result = np.eye(4)
    result[:3, :3], result[:3, 3] = rotation, translation
    return result


def poses(path):
    values = np.loadtxt(path, delimiter=',', ndmin=2)
    return np.stack([pose(r, t) for r, t in zip(
        Rotation.from_quat(values[:, [1,2,3,0]]).as_matrix(), values[:, 4:])])


def physical_x(x, y):
    return np.r_[x[:3,3], y[:3,3], x[:3,:3].ravel(order='F'), y[:3,:3].ravel(order='F'), 1.]


def lifted_residual(z, A, B):
    tx, ty = z[:3], z[3:6]
    rx, ry = z[6:15].reshape(3,3,order='F'), z[15:24].reshape(3,3,order='F')
    rr = A[:,:3,:3]@rx - ry@B[:,:3,:3]
    rt = A[:,:3,:3]@tx - ty - B[:,:3,3]@ry.T + z[24]*A[:,:3,3]
    return np.c_[np.sqrt(125)*rr.reshape(-1,9), np.sqrt(5000)*rt]


def pad(*values):
    return 1e-8 + 2e-12*sum(abs(v) for v in values)


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    verify()
    assert output != ROOT/'reference', 'Published reference results must remain unchanged'
    protocol = json.loads((ROOT/'protocol.json').read_text())
    original = {float(r['tau2']):r for r in csv.DictReader((ROOT/'reference/cutoff_results.csv').open())}
    A, B = [poses(ROOT/f'input/{name}.csv') for name in ['A','B']]
    X, Y = [np.loadtxt(ROOT/f'input/{name}_candidate.csv', delimiter=',') for name in ['X','Y']]
    z = physical_x(X,Y)
    left, right = A@X, Y@B
    E = left-right
    costs = 125*np.sum(E[:,:3,:3]**2,axis=(1,2)) + 5000*np.sum(E[:,:3,3]**2,axis=1)
    translation = np.linalg.norm(E[:,:3,3],axis=1)*1000
    rotation = np.degrees(np.arccos(np.clip((np.trace(left[:,:3,:3].transpose(0,2,1)@right[:,:3,:3],axis1=1,axis2=2)-1)/2,-1,1)))
    assert abs(np.sqrt(np.mean(translation**2))-7.777713574448693) < 1e-7
    assert abs(np.sqrt(np.mean(rotation**2))-0.9599486355958229) < 1e-7
    samples = json.loads((ROOT/'input/sample_ids.json').read_text())
    write_csv(output/'residuals_by_sample.csv', [dict(sample_id=s,translation_mm=float(t),rotation_deg=float(r),cost=float(c)) for s,t,r,c in zip(samples,translation,rotation,costs)])
    design = np.stack([lifted_residual(v,A,B) for v in np.eye(25)],axis=-1)
    base_Q = np.einsum('nri,nrj->nij',design,design)
    assert np.max(abs(np.einsum('i,nij,j->n',z,base_Q,z)-costs)) < 1e-8
    rng = np.random.default_rng(2026111905)
    random_points = [physical_x(pose(Rotation.random(random_state=rng).as_matrix(),rng.normal(size=3)),
                               pose(Rotation.random(random_state=rng).as_matrix(),rng.normal(size=3))) for _ in range(3)]
    rows, curves, diagnostics = [], [], {}
    max_errors = dict(q=0., gamma=0., score=0., constraint_identity=0.)
    for tau in protocol['diagnostic_cutoffs']:
        name = f'cutoff_{tau:.2f}'.replace('.', 'p')
        for filename in ['A.csv','B.csv','X_candidate.csv','Y_candidate.csv']:
            assert digest(output/'cases'/name/filename) == digest(ROOT/'input'/filename)
        d = toml.load(output/'diagnostics'/name/'result.toml')
        diagnostics[tau] = d
        q, Qs = costs/tau, base_Q/tau
        error = float(np.max(abs(q-np.array(d['q']))))
        max_errors['q'] = max(max_errors['q'],error)
        assert error < 1e-8
        assert bool(np.all(q<1)) == d['full_support']
        assert int(sum(q<1)) == d['kept'] and d['N'] == 44 and d['sdp_status'] == 'OPTIMAL'
        S = np.loadtxt(output/'diagnostics'/name/'S.csv',delimiter=',')
        H = S[:24,:24]
        assert np.linalg.eigvalsh(H)[0] > 0
        M = Qs.sum(0)-S
        for zz in [z]+random_points:
            error = abs(float(zz@M@zz)-d['beta'])
            max_errors['constraint_identity'] = max(max_errors['constraint_identity'],error)
            assert error < 3e-6
        L = np.linalg.cholesky(H)
        x0 = np.r_[-np.linalg.solve(H,S[:24,24]),1.]
        cross = float(S[:24,24]@x0[:24])
        gamma = d['beta']+S[24,24]+cross-pad(d['beta'],S[24,24],cross)
        error = abs(gamma-d['lower'])
        max_errors['gamma'] = max(max_errors['gamma'],error)
        assert error < 3e-7
        assert abs((q.sum()-gamma)/max(1.,q.sum())-d['relative_ls_gap']) < 1e-7
        row = dict(tau2=tau,full_support=d['full_support'],kept=d['kept'],max_q=float(q.max()),
                   ls_cost=float(q.sum()),tls_cost=float(np.minimum(q,1).sum()),kmax=d.get('kmax',''),
                   min_H_eigenvalue=d['min_H_eigenvalue'],relative_ls_gap=d['relative_ls_gap'],failure_class=d['failure_class'])
        if d['full_support']:
            assert d['kmax'] == min(44,math.floor(float(q.sum())+1e-7))
            Li = np.linalg.inv(L)
            Vs = Li@Qs[:,:24,:24]@Li.T
            rho = np.maximum(0.,np.einsum('i,nij,j->n',x0,Qs,x0))
            rho += pad(float(rho.max()))
            kappa = np.linalg.eigvalsh(Vs)[:,-1]+1e-9
            pairs = np.array([(i,j) for j in range(1,44) for i in range(j)])
            pk = np.linalg.eigvalsh(Vs[pairs[:,0]]+Vs[pairs[:,1]])[:,-1]+1e-9
            pr = rho[pairs].sum(1)
            for k,budget in enumerate(d['budgets'],1):
                assert budget > 0 and abs(budget-(k-(q.sum()-gamma))) < 1e-7
                weights = kappa+rho/budget
                single = float(np.sort(weights)[-k:].sum())
                pair = float((k//2)*np.max(pk+pr/budget)+(k%2)*np.max(weights))
                for mode,value in [('single',single),('pair',pair),('cascade',min(single,pair))]:
                    error = abs(value-d[mode+'_scores'][k-1])
                    max_errors['score'] = max(max_errors['score'],error)
                    assert error < 3e-7
                curves.append(dict(tau2=tau,k=k,single=single,pair=pair,cascade=min(single,pair)))
        for mode in protocol['methods']:
            ok = d['full_support'] and d['gap_pass'] and d['budget_positive'] and all(v<1-1e-7 for v in d[mode+'_scores'])
            assert ok == d[mode+'_certified'] == (original[tau][mode+'_certified']=='True')
            row[mode+'_certified'] = ok
            row[mode+'_max_bound'] = max(d.get(mode+'_scores',[]),default='')
        assert row['failure_class'] == original[tau]['failure_class']
        rows.append(row)
    timings = toml.load(output/'timings.toml')
    runs = timings['runs']
    assert len(runs) == 324 and timings['blas_threads'] == timings['julia_threads'] == 1
    time_rows = []
    for tau in protocol['timed_cutoffs']:
        d = diagnostics[tau]
        for mode in protocol['methods']:
            selected = [r for r in runs if r['tau2']==tau and r['mode']==mode]
            assert len(selected) == 9 and sorted(r['repeat'] for r in selected) == list(range(1,10))
            expected = 'inapplicable' if not d['full_support'] else 'numerically_certified' if d[mode+'_certified'] else 'inconclusive'
            assert all(r['status']==expected for r in selected)
            for r in selected:
                if not d['full_support']:
                    continue
                assert r['sdp_status'] == 'OPTIMAL'
                if mode != 'cascade':
                    scores = d[mode+'_scores'][:len(r['scores'])]
                else:
                    scores = d['single_scores'].copy()
                    for k,value in enumerate(scores):
                        if value < 1-1e-7:
                            continue
                        scores[k] = min(value,d['pair_scores'][k])
                        if scores[k] >= 1-1e-7:
                            break
                assert np.max(np.abs(np.array(r['scores'])-scores),initial=0) < 3e-7
            record = dict(tau2=tau,method=mode,status=expected,repeats=9)
            for stage in ['input','anchor','check','total']:
                values = np.array([r[stage+'_seconds']*1000 for r in selected])
                for stat,value in zip(['p25_ms','median_ms','p75_ms'],np.quantile(values,[.25,.5,.75])):
                    record[stage+'_'+stat] = float(value)
            time_rows.append(record)
    pair_only = [r['tau2'] for r in rows if r['pair_certified'] and not r['single_certified']]
    assert pair_only == [i/100 for i in range(330,406,5)]
    write_csv(output/'cutoff_results.csv',rows)
    write_csv(output/'bound_curves.csv',curves)
    write_csv(output/'timing_summary.csv',time_rows)
    write_csv(output/'timing_runs.csv',[{k:r.get(k,'') for k in ['tau2','mode','repeat','order_index','status','reason','input_seconds','anchor_seconds','check_seconds','total_seconds']} for r in runs])
    summary = dict(observation_count=44,unscaled_ls_cost=float(costs.sum()),max_unscaled_observation_cost=float(costs.max()),
                   translation_rms_mm=float(np.sqrt(np.mean(translation**2))),rotation_rms_deg=float(np.sqrt(np.mean(rotation**2))),
                   pair_only_tested_cutoffs=pair_only,first_single_certified=min(r['tau2'] for r in rows if r['single_certified']),
                   first_pair_certified=min(r['tau2'] for r in rows if r['pair_certified']),timing_summary=time_rows,
                   scope='Real44 fixed-candidate numerical certification. Timings belong to this run; physical accuracy is not measured.')
    validation = dict(passed=True,observations=44,diagnostics_checked=len(rows),bounds_checked=len(curves),
                      timed_calls_checked=len(runs),paper_decisions_match=True,max_absolute_errors=max_errors)
    (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    (output/'validation.json').write_text(json.dumps(validation,indent=2)+'\n')
    print(json.dumps(validation,indent=2))


if __name__ == '__main__':
    main()
