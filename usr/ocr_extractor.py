import re
import os
from datetime import datetime

OCRSPACE_API_KEY = "K86411242588957"
MY_COMPANY_NAME = "LA POSADA DE DANIEL"
MY_COMPANY_RIF = "J316636151"


def _extract_from_image_ocrspace(image_path: str) -> str:
    """Extrae texto usando OCR.SPACE API (gratuito, 1000 req/día)."""
    import base64
    import requests
    if not os.path.exists(image_path):
        print(f"[OCR.SPACE] Archivo no encontrado: {image_path}")
        return None

    file_size = os.path.getsize(image_path)
    if file_size > 1_000_000:
        try:
            from PIL import Image
            img = Image.open(image_path)
            max_side = 1800
            if max(img.size) > max_side:
                ratio = max_side / max(img.size)
                new_size = (int(img.size[0] * ratio), int(img.size[1] * ratio))
                img = img.resize(new_size, Image.LANCZOS)
            img.save(image_path, 'PNG', optimize=True)
        except Exception as e:
            print(f"[OCR.SPACE] Compresión fallida: {e}")

    with open(image_path, 'rb') as f:
        img_data = base64.b64encode(f.read()).decode('utf-8')

    headers = {'apikey': OCRSPACE_API_KEY}

    try:
        response = requests.post(
            'https://api.ocr.space/parse/image',
            data={
                'base64Image': f"data:image/png;base64,{img_data}",
                'language': 'spa',
                'isOverlayRequired': 'false',
                'detectOrientation': 'true',
                'scale': 'true',
                'OCREngine': '2',
            },
            headers=headers,
            timeout=30
        )

        if not response.content:
            return None

        try:
            result = response.json()
        except Exception:
            return None

        if result.get("IsErroredOnProcessing"):
            return None

        parsed_results = result.get("ParsedResults", [])
        if not parsed_results:
            return None

        full_text = "\n".join(r.get("ParsedText", "") for r in parsed_results)
        return full_text.strip() if full_text.strip() else None
    except Exception as e:
        print(f"[OCR.SPACE] Exception: {e}")
        return None


def parse_factura_text(text: str) -> dict:
    data = {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}
    text = text.strip()
    
    # 1. Buscar Proveedor
    prov_section = text
    for line in text.split('\n'):
        if re.search(r'\b(Proveedor|Emitido por|Vendido por)\b', line, re.IGNORECASE):
            prov_section = re.sub(r'^[^:]*:\s*', '', line).strip()
            break

    prov_match = re.search(r'([A-Z][A-Z0-9\s,]*C\.?\s*A\.?)', prov_section, re.IGNORECASE)
    if not prov_match:
        prov_match = re.search(r'([A-Z][A-Z0-9\s,]*S\.?\s*A\.?)', prov_section, re.IGNORECASE)
    
    if prov_match:
        candidate = prov_match.group(1).strip()
        if MY_COMPANY_NAME.upper() not in candidate.upper():
            data["proveedor"] = candidate
    elif not data["proveedor"]:
        prov_match2 = re.search(r'([A-Z][A-Z0-9\s,]*C\.?\s*A\.?)', text, re.IGNORECASE)
        if prov_match2:
            candidate = prov_match2.group(1).strip()
            if MY_COMPANY_NAME.upper() not in candidate.upper():
                data["proveedor"] = candidate

    # 2. Buscar RIF (Filtramos el RIF de la propia empresa)
    rif_match = re.search(r'R\.?I\.?F\.?\s*[-]?\s*C\.?I\.?\s*[:.]?\s*J[\s-]*(\d{8,9})', text, re.IGNORECASE)
    if rif_match:
        found_rif = "J" + rif_match.group(1)
        if found_rif != MY_COMPANY_RIF:
            data["rif"] = found_rif

    # 3. Buscar Número de Documento (Factura, Nota, Entrada, etc)
    nro_match = re.search(r'(?:FACTURA|NOTA\s*DE\s*ENTREGA|ENTRADA|DOC|NRO|NUM)\s*#?\s*[:.]?\s*(\d{4,10})', text, re.IGNORECASE)
    if nro_match:
        data["nro_factura"] = nro_match.group(1)

    # 4. Buscar Fecha
    fecha_match = re.search(r'Fecha\s*:\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{2,4})', text, re.IGNORECASE)
    if fecha_match:
        dia, mes = int(fecha_match.group(1)), int(fecha_match.group(2))
        anio = fecha_match.group(3)
        if len(anio) == 2:
            anio = "20" + anio
        data["fecha"] = f"{dia:02d}/{mes:02d}/{anio}"

    return data


def _get_easyocr_reader():
    if not hasattr(_get_easyocr_reader, 'reader'):
        try:
            import easyocr
            _get_easyocr_reader.reader = easyocr.Reader(['es', 'en'], gpu=False, verbose=False)
        except Exception:
            _get_easyocr_reader.reader = None
    return _get_easyocr_reader.reader


def extract_from_image(image_path: str, use_preprocessing: bool = True) -> dict:
    if not image_path:
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}

    # 1. OCR.SPACE (Primario)
    raw = _extract_from_image_ocrspace(image_path)
    if raw:
        return parse_factura_text(raw)

    # 2. Tesseract (Fallback 1)
    full_text = ""
    try:
        import pytesseract
        from PIL import Image
        img = Image.open(image_path)
        full_text = pytesseract.image_to_string(img, lang='spa', config=r'--oem 3 --psm 6')
    except Exception:
        pass

    # 3. EasyOCR (Fallback 2)
    if not full_text.strip():
        try:
            reader = _get_easyocr_reader()
            if reader:
                result = reader.readtext(image_path)
                full_text = " ".join([det[1] for det in result])
        except Exception:
            pass

    if not full_text.strip():
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
