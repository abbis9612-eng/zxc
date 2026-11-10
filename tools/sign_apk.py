"""توقيع APK بمخطط التوقيع v2 من Android (موثّق علناً)، بلا أدوات Android SDK.

يُستخدم لنسخ التجربة فقط. نسخة المتجر تحتاج مفتاحاً خاصاً سرياً لا يُحفظ في المستودع.

الاستعمال:
    python3 tools/sign_apk.py <input-unsigned.apk> <output-signed.apk> [key.pem]

إن لم يوجد ملف المفتاح يُنشأ مفتاح RSA 2048 مع شهادة ذاتية التوقيع ويُحفظ،
حتى تُوقّع كل النسخ بنفس المفتاح وتُثبّت التحديثات فوق النسخة القديمة.

المرجع: https://source.android.com/docs/security/features/apksigning/v2
"""
import datetime
import hashlib
import os
import struct
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

APK_SIG_BLOCK_MAGIC = b"APK Sig Block 42"
V2_BLOCK_ID = 0x7109871A
RSA_PKCS1_SHA256 = 0x0103
CHUNK = 1024 * 1024


def u32(n):
    return struct.pack("<I", n)


def u64(n):
    return struct.pack("<Q", n)


def lp(b):
    """بيانات مسبوقة بطولها (uint32)"""
    return u32(len(b)) + b


def load_or_create_key(path):
    if os.path.exists(path):
        data = open(path, "rb").read()
        key = serialization.load_pem_private_key(data, password=None)
        cert = x509.load_pem_x509_certificate(data)
        return key, cert
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "WW3 Test Build")])
    now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name).issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=365 * 30))
        .sign(key, hashes.SHA256())
    )
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    print("أُنشئ مفتاح توقيع جديد:", path)
    return key, cert


def find_eocd(data):
    # نهاية الدليل المركزي: التوقيع 0x06054b50، ويجوز أن يليه تعليق حتى 65535 بايت
    sig = b"PK\x05\x06"
    start = max(0, len(data) - 22 - 65535)
    i = data.rfind(sig, start)
    if i < 0:
        raise SystemExit("ليس ملف ZIP صالحاً")
    return i


def chunk_digest(sections):
    digests = []
    for sec in sections:
        for off in range(0, len(sec), CHUNK):
            c = sec[off:off + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + u32(len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + u32(len(digests)) + b"".join(digests)).digest()


def sign(inp, out, key_path):
    data = open(inp, "rb").read()
    eocd_off = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd_off + 12:eocd_off + 20])
    if data[cd_off - 16:cd_off] == APK_SIG_BLOCK_MAGIC:
        raise SystemExit("الملف موقّع مسبقاً بمخطط v2 أو أحدث")
    entries = data[:cd_off]
    central = data[cd_off:cd_off + cd_size]
    eocd = data[eocd_off:]

    key, cert = load_or_create_key(key_path)
    # البصمة تُحسب والـ EOCD يشير إلى بداية كتلة التوقيع (= موضع الدليل المركزي الأصلي)
    digest = chunk_digest([entries, central, eocd])

    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    digests = lp(lp(u32(RSA_PKCS1_SHA256) + lp(digest)))
    certs = lp(lp(cert_der))
    attrs = lp(b"")
    signed_data = digests + certs + attrs
    signature = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    signatures = lp(lp(u32(RSA_PKCS1_SHA256) + lp(signature)))
    signer = lp(signed_data) + signatures + lp(pub_der)
    v2_value = lp(lp(signer))

    pair = u32(V2_BLOCK_ID) + v2_value
    pairs = u64(len(pair)) + pair
    block_size = len(pairs) + 8 + 16
    block = u64(block_size) + pairs + u64(block_size) + APK_SIG_BLOCK_MAGIC

    new_cd_off = cd_off + len(block)
    new_eocd = eocd[:16] + u32(new_cd_off) + eocd[20:]
    with open(out, "wb") as f:
        f.write(entries + block + central + new_eocd)
    print("وُقّع:", out, "(%d بايت)" % (len(entries) + len(block) + len(central) + len(new_eocd)))


def verify(path):
    """تحقق ذاتي: يعيد حساب البصمة ويتحقق من التوقيع بالمفتاح العام المضمّن."""
    data = open(path, "rb").read()
    eocd_off = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd_off + 12:eocd_off + 20])
    assert data[cd_off - 16:cd_off] == APK_SIG_BLOCK_MAGIC, "لا توجد كتلة توقيع"
    block_size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
    block_start = cd_off - block_size - 8
    pairs = data[block_start + 8:cd_off - 24]
    i = 0
    v2 = None
    while i < len(pairs):
        ln = struct.unpack("<Q", pairs[i:i + 8])[0]
        pid = struct.unpack("<I", pairs[i + 8:i + 12])[0]
        if pid == V2_BLOCK_ID:
            v2 = pairs[i + 12:i + 8 + ln]
        i += 8 + ln
    assert v2 is not None, "لا توجد كتلة v2"

    def take(b, o):
        n = struct.unpack("<I", b[o:o + 4])[0]
        return b[o + 4:o + 4 + n], o + 4 + n

    signers, _ = take(v2, 0)
    signer, _ = take(signers, 0)
    signed_data, o = take(signer, 0)
    sigs, o = take(signer, o)
    pub, o = take(signer, o)
    sig_entry, _ = take(sigs, 0)
    alg = struct.unpack("<I", sig_entry[:4])[0]
    sig, _ = take(sig_entry, 4)
    serialization.load_der_public_key(pub).verify(sig, signed_data, padding.PKCS1v15(), hashes.SHA256())
    digs, _ = take(signed_data, 0)
    dig_entry, _ = take(digs, 0)
    want, _ = take(dig_entry, 4)
    eocd = bytearray(data[eocd_off:])
    eocd[16:20] = u32(block_start)
    got = chunk_digest([data[:block_start], data[cd_off:eocd_off], bytes(eocd)])
    assert got == want and alg == RSA_PKCS1_SHA256, "البصمة لا تطابق"
    print("التحقق ناجح: توقيع v2 سليم والبصمة مطابقة")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    key_file = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), "keys", "test-signing.pem")
    sign(sys.argv[1], sys.argv[2], key_file)
    verify(sys.argv[2])
