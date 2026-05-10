import re
import os
from datetime import datetime

GEMINI_API_KEY = "AIzaSyBfh9cassXz_MMYMFAZGtRxhlSccKcXQ6g"
OCRSPACE_API_KEY = "K86411242588957"

GEMINI_MODELS = [
    "gemini-3.1-flash-lite-preview",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
]


def _is_quota_exceeded(exc):
    err_str = str(exc).lower()
    return "429" in err_str or "resource_exhausted" in err_str or "quota" in err_str or "exceeded" in err_str


def _extract_from_image_gemini(image_path: str, model: str) -> str:
    from google import genai
    import PIL.Image
    client = genai.Client(api_key=GEMINI_API_KEY)
    img = PIL.Image.open(image_path)
    prompt = (
        "Devuelve TODO el texto visible en esta imagen de factura. "
        "Transcribe cada línea tal como aparece, en el mismo orden. "
        "No resumas, no interpretes, no omitas nada."
    )
    response = client.models.generate_content(
        model=model,
        contents=[prompt, img]
    )
    if response.text:
        return response.text.strip()
    return ""


def _extract_from_image_gemini_json(image_path: str, model: str) -> dict:
    from google import genai
    import PIL.Image
    import json
    client = genai.Client(api_key=GEMINI_API_KEY)
    img = PIL.Image.open(image_path)
    prompt = (
        'Analiza este documento de recepción. Extrae los datos en formato JSON.\n\n'
        'Campos: proveedor, rif, nro_factura, fecha (DD/MM/AAAA)\n\n'
        'REGLAS:\n'
        '- El RIF es del PROVEEDOR, NO del receptor\n'
        '- Si no encuentras un dato, usa null\n'
        '- Devuelve SOLO JSON válido\n\n'
        'Ejemplo: {"proveedor": "DISTRIBUIDORA X, C.A.", "rif": "J308793728", "nro_factura": "000063455", "fecha": "09/05/2026"}'
    )
    response = client.models.generate_content(
        model=model,
        contents=[prompt, img]
    )
    if response.text:
        raw = response.text.strip()
        for line in raw.split('\n'):
            line = line.strip()
            if line.startswith('{'):
                return json.loads(line)
    return None


def _extract_from_image_ocrspace(image_path: str) -> dict:
    """Extrae texto usando OCR.SPACE API (gratuito, 1000 req/día)."""
    import base64
    import requests
    if not os.path.exists(image_path):
        print(f"[OCR.SPACE] Archivo no encontrado: {image_path}")
        return None

    with open(image_path, 'rb') as f:
        img_data = base64.b64encode(f.read()).decode('utf-8')

    payload = {
        'base64Image': f"data:image/png;base64,{img_data}",
        'language': 'spa',
        'isOverlayRequired': 'false',
        'detectOrientation': 'true',
        'scale': 'true',
        'OCREngine': 2,
    }
    headers = {'apikey': OCRSPACE_API_KEY}

    try:
        print(f"[OCR.SPACE] Enviando imagen...")
        response = requests.post(
            'https://api.ocr.space/parse/image',
            data=payload,
            headers=headers,
            timeout=30
        )
        result = response.json()

        if result.get("IsErroredOnProcessing"):
            print(f"[OCR.SPACE] Error: {result.get('ErrorMessage')}")
            return None

        parsed_results = result.get("ParsedResults", [])
        if not parsed_results:
            print(f"[OCR.SPACE] Sin texto detectado")
            return None

        full_text = "\n".join(r.get("ParsedText", "") for r in parsed_results)
        if full_text.strip():
            print(f"[OCR.SPACE] OK: {len(full_text)} chars")
            return full_text.strip()
        return None
    except Exception as e:
        print(f"[OCR.SPACE] Exception: {e}")
        return None


def parse_factura_text(text: str) -> dict:
    data = {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}

    text = text.strip()
    prov_section = text
    for line in text.split('\n'):
        if re.search(r'\bProveedor\b', line, re.IGNORECASE):
            clean_line = re.sub(r'^[^:]*:\s*', '', line).strip()
            prov_section = clean_line
            break

    prov_match = re.search(r'([A-Z][A-Z0-9\s,]*C\.?\s*A\.?)', prov_section, re.IGNORECASE)
    if not prov_match:
        prov_match = re.search(r'([A-Z][A-Z0-9\s,]*S\.?\s*A\.?)', prov_section, re.IGNORECASE)
    if prov_match:
        print(f"[PARSE] Proveedor (1): '{prov_match.group(1).strip()}'")
        data["proveedor"] = prov_match.group(1).strip()

    if not data["proveedor"]:
        prov_match2 = re.search(r'([A-Z][A-Z0-9\s,]*C\.?\s*A\.?)', text, re.IGNORECASE)
        if prov_match2:
            candidate = prov_match2.group(1).strip()
            if 'POSADA DE DANIEL' not in candidate.upper():
                print(f"[PARSE] Proveedor (fallback): '{candidate}'")
                data["proveedor"] = candidate

    rif_match = re.search(r'R\.?I\.?F\.?\s*[-]?\s*C\.?I\.?\s*[:.]?\s*J[\s-]*(\d{8,9})', text, re.IGNORECASE)
    if rif_match:
        data["rif"] = "J" + rif_match.group(1)
        print(f"[PARSE] RIF: {data['rif']}")

    nro_match = re.search(r'FACTURA\s*#\s*(\d{4,10})', text, re.IGNORECASE)
    if nro_match:
        data["nro_factura"] = nro_match.group(1)
        print(f"[PARSE] Factura: {data['nro_factura']}")

    fecha_match = re.search(r'Fecha\s*:\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{2,4})', text, re.IGNORECASE)
    if fecha_match:
        dia, mes = int(fecha_match.group(1)), int(fecha_match.group(2))
        anio = fecha_match.group(3)
        if len(anio) == 2:
            anio = "20" + anio
        data["fecha"] = f"{dia:02d}/{mes:02d}/{anio}"
        print(f"[PARSE] Fecha: {data['fecha']}")

    print(f"[PARSE] Resultado: {data}")
    return data


def _get_easyocr_reader():
    if not hasattr(_get_easyocr_reader, 'reader'):
        try:
            import easyocr
            print("[OCR] Init EasyOCR...")
            _get_easyocr_reader.reader = easyocr.Reader(['es', 'en'], gpu=False, verbose=False)
            print("[OCR] EasyOCR ready")
        except Exception as e:
            print(f"[OCR] EasyOCR error: {e}")
            _get_easyocr_reader.reader = None
    return _get_easyocr_reader.reader


def extract_from_image(image_path: str, use_preprocessing: bool = True) -> dict:
    if not image_path:
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}

    # 1. OCR.SPACE (primario)
    raw = _extract_from_image_ocrspace(image_path)
    if raw:
        return parse_factura_text(raw)

    # 2. Gemini JSON (fallback 1)
    for model in GEMINI_MODELS:
        try:
            data = _extract_from_image_gemini_json(image_path, model)
            if data:
                clean = {
                    "proveedor": data.get("proveedor") or "",
                    "rif": data.get("rif") or "",
                    "nro_factura": data.get("nro_factura") or "",
                    "fecha": data.get("fecha") or "",
                }
                if any(clean.values()):
                    print(f"[OCR] {model} JSON OK: {clean}")
                    return clean
        except Exception as e:
            if _is_quota_exceeded(e):
                print(f"[OCR] {model} agotado, siguiente...")
                continue
            print(f"[OCR] {model}: {e}")
            break

    # 3. Gemini texto libre + regex (fallback 2)
    for model in GEMINI_MODELS:
        try:
            full_text = _extract_from_image_gemini(image_path, model)
            if full_text.strip():
                print(f"[OCR] {model} texto OK: {len(full_text)} chars")
                return parse_factura_text(full_text.strip())
        except Exception as e:
            if _is_quota_exceeded(e):
                print(f"[OCR] {model} agotado, siguiente...")
                continue
            print(f"[OCR] {model}: {e}")
            break

    # 4. Tesseract
    print("[OCR] Intentando Tesseract...")
    full_text = ""
    try:
        import pytesseract
        from PIL import Image
        img = Image.open(image_path)
        full_text = pytesseract.image_to_string(img, lang='spa', config=r'--oem 3 --psm 6')
        if full_text.strip():
            print(f"[OCR] Tesseract OK: {len(full_text)} chars")
    except ImportError:
        print("[OCR] Tesseract no instalado")
    except Exception as e:
        print(f"[OCR] Tesseract: {e}")

    # 5. EasyOCR
    if not full_text.strip():
        print("[OCR] Intentando EasyOCR...")
        try:
            reader = _get_easyocr_reader()
            if reader:
                result = reader.readtext(image_path)
                for detection in result:
                    full_text += detection[1] + " "
                if full_text.strip():
                    print(f"[OCR] EasyOCR OK: {len(full_text)} chars")
        except Exception as e:
            print(f"[OCR] EasyOCR: {e}")

    if not full_text.strip():
        print("[OCR] No text extracted")
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}

    return parse_factura_text(full_text.strip())


def preprocess_image(image_path: str) -> str:
    try:
        import cv2
        if not os.path.exists(image_path):
            return image_path
        img = cv2.imread(image_path)
        if img is None:
            return image_path
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        processed = image_path.replace('.png', '_proc.png').replace('.jpg', '_proc.jpg')
        cv2.imwrite(processed, thresh)
        return processed
    except:
        return image_path


def check_proveedor_exists(proveedor_nombre: str, rif: str = "") -> dict:
    from usr.database.local_replica import LocalReplica
    proveedores = LocalReplica.get_proveedores(estado="Activo")
    nombre_lower = proveedor_nombre.lower().strip() if proveedor_nombre else ""

    for p in proveedores:
        if nombre_lower and nombre_lower in p.get('nombre', '').lower():
            return {"existe": True, "nombre": p['nombre']}

    return {"existe": False, "nombre": ""}


if __name__ == "__main__":
    test = "Proveedor: CENTRAL SANTO TOME, C.A.\nR.I.F-C.I.: J308793728\nFecha: 07/05/2026\nNro: FACTURA #000028852"
    print(parse_factura_text(test))
