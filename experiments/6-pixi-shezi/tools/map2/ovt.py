# تنزيل بيانات Overture Maps لمنطقة الخريطة (طرق، بيوت، مياه، استخدام أرض) بفلترة الصندوق المحيط
import pyarrow.fs as pfs, pyarrow.dataset as ds, pyarrow.parquet as pq, os, time, sys
X0, Y0, X1, Y1 = 42.60, 36.45, 43.30, 37.05
fs = pfs.S3FileSystem(anonymous=True, region='us-west-2', proxy_options=os.environ['HTTPS_PROXY'], tls_ca_file_path='/root/.ccr/ca-bundle.crt')
REL = 'overturemaps-us-west-2/release/2026-10-21.0'
for theme, typ in [('transportation', 'segment'), ('buildings', 'building'), ('base', 'water'), ('base', 'land_use'), ('base', 'land_cover'), ('base', 'infrastructure'), ('places', 'place'), ('divisions', 'division')]:
    t = time.time(); out = f'{typ}.parquet'
    if os.path.exists(out): print('skip', out); continue
    d = ds.dataset(f'{REL}/theme={theme}/type={typ}/', filesystem=fs, format='parquet')
    b = ds.field('bbox')
    f = (ds.field('bbox', 'xmax') >= X0) & (ds.field('bbox', 'xmin') <= X1) & (ds.field('bbox', 'ymax') >= Y0) & (ds.field('bbox', 'ymin') <= Y1)
    tb = d.to_table(filter=f)
    pq.write_table(tb, out)
    print(typ, tb.num_rows, 'rows', round(time.time() - t), 's', flush=True)
print('ALL DONE')
