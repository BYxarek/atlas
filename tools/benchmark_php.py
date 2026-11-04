"""Measure real storage transactions using concurrent PHP workers and isolated data."""
import argparse
import json
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from fetch_php import php_binary

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=8)
    parser.add_argument('--requests', type=int, default=20)
    parser.add_argument('--rooms', type=int, default=4)
    args = parser.parse_args()
    if not (1 <= args.workers <= 64 and 1 <= args.requests <= 1000 and 1 <= args.rooms <= 16):
        parser.error('workers 1..64, requests 1..1000, rooms 1..16')
    php = php_binary()
    with tempfile.TemporaryDirectory(prefix='atlas-load-') as temporary:
        worker = Path(temporary) / 'worker.php'
        worker.write_text('''<?php
require $argv[1].'/hosting/service.php';
$config=['data_dir'=>$argv[2],'metrics'=>true,'lease_seconds'=>20];
for($i=0;$i<(int)$argv[3];$i++) atlas_transaction($config,function(&$state)use($argv,$config){
    $sim=new AtlasWorld();
    if (!$state['rooms']) for($r=0;$r<(int)$argv[4];$r++) {
        $w=$sim->create(); $sim->add($w,'a',0,'69dfbd'); $sim->add($w,'b',1,'73aeef');
        $state['rooms'][]=['world'=>$w];
    }
    foreach($state['rooms'] as &$room) $sim->tick($room['world'],['a','b']);
    $state['counter']=($state['counter']??0)+1;
    return [];
});
''', encoding='utf-8')
        def run(_):
            return subprocess.run([str(php), str(worker), str(ROOT), temporary, str(args.requests), str(args.rooms)],
                                  capture_output=True, text=True, check=True).stderr
        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            logs = list(pool.map(run, range(args.workers)))
        duration = time.perf_counter() - started
        metrics = [json.loads(m.group(1)) for log in logs for m in re.finditer(r'ATLAS metric (\{[^\n]+\})', log)]
        state = json.loads((Path(temporary) / 'state.php').read_text().split('\n', 1)[1])
        expected = args.workers * args.requests
        assert state['counter'] == expected and len(metrics) == expected, 'Lost update or metric'
        result = dict(workers=args.workers, rooms=args.rooms, transactions=expected, seconds=duration,
                      transactions_per_second=expected / duration, state_bytes=metrics[-1]['state_bytes'])
        for key in ['lock_ms', 'transaction_ms']:
            values = sorted(m[key] for m in metrics)
            result[key] = dict(median=statistics.median(values), p95=values[int((len(values)-1)*.95)], maximum=max(values))
        output = ROOT / 'build/php-benchmark.json'
        output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
