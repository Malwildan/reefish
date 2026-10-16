"""Audit dan split klorofil; identitas blok adalah urutan berkas, bukan tanggal."""
import argparse, csv, hashlib, json, math
from pathlib import Path
from collections import Counter


def prepare(source, reference, output):
    source, reference, output = Path(source), Path(reference), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    with reference.open(encoding='utf-8-sig', newline='') as f:
        ref = list(csv.DictReader(f))
    keys = [(int(r['grid_x']), int(r['grid_y'])) for r in ref]
    coords = [(float(r['latitude']), float(r['longitude'])) for r in ref]
    if len(keys) != 31354 or len(set(keys)) != len(keys):
        raise ValueError('Referensi harus memiliki 31354 key unik')
    expected = ['grid_x', 'grid_y', 'latitude', 'longitude', 'value']
    blocks, current, values, starts = [], [], [], []
    counts = Counter()
    with source.open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != expected:
            raise ValueError(f'Schema tidak sesuai: {reader.fieldnames}')
        for row_num, row in enumerate(reader, 2):
            if None in row or any(row[k] is None for k in expected):
                raise ValueError(f'Jumlah field tidak sesuai, baris {row_num}')
            nums = {k: float(row[k]) for k in expected}
            if not all(math.isfinite(v) for v in nums.values()):
                raise ValueError(f'Angka invalid, baris {row_num}')
            if not nums['grid_x'].is_integer() or not nums['grid_y'].is_integer():
                raise ValueError(f'Indeks pecahan, baris {row_num}')
            index = len(current)
            key = (int(nums['grid_x']), int(nums['grid_y']))
            if key != keys[index]:
                raise ValueError(f'Urutan/isi grid berbeda pada baris {row_num}')
            if (nums['latitude'], nums['longitude']) != coords[index]:
                raise ValueError(f'Koordinat berbeda pada baris {row_num}')
            if not (-9.15 <= nums['latitude'] <= -8.35 and
                    112.25 <= nums['longitude'] <= 113.10):
                raise ValueError(f'Koordinat luar AOI, baris {row_num}')
            if index == 0: starts.append(row_num)
            current.append(row)
            values.append(nums['value'])
            counts[key] += 1
            if len(current) == len(keys):
                number = len(blocks) + 1
                path = output / f'blok_{number:02d}.csv'
                with path.open('w', encoding='utf-8', newline='') as dst:
                    writer = csv.DictWriter(dst, fieldnames=expected, lineterminator='\n')
                    writer.writeheader()
                    writer.writerows(current)
                vs = [float(r['value']) for r in current]
                blocks.append({'block_index': number, 'label': f'Blok {number}',
                    'observed_at': None, 'file': path.name, 'rows': len(current),
                    'source_start_line': starts[-1], 'source_end_line': row_num,
                    'value_min': min(vs), 'value_max': max(vs),
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
                current = []
    if current or len(blocks) != 24 or set(counts.values()) != {24}:
        raise ValueError('Snapshot harus 24 blok lengkap, masing-masing 31354 sel')
    result = {'source_file': source.name, 'source_bytes': source.stat().st_size,
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'columns': expected, 'rows': len(values), 'unique_grid_keys': len(keys),
        'block_count': len(blocks), 'rows_per_block': len(keys),
        'same_key_order_as_reference_every_block': True,
        'max_coordinate_delta_deg': 0.0, 'outside_aoi_rows': 0,
        'nonfinite_rows': 0, 'unit': None, 'time_axis': None,
        'block_meaning': 'source_file_order_only_not_verified_time',
        'value_min': min(values), 'value_max': max(values),
        'zero_value_count': sum(v == 0 for v in values),
        'negative_value_count': sum(v < 0 for v in values), 'blocks': blocks}
    (output / 'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = prepare(args.input, args.reference, args.output)
    print(f"Selesai: {report['block_count']} blok; {report['rows']} baris. Unit/waktu belum diketahui.")
