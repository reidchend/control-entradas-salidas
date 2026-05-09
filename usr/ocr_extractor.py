import re
import os
from datetime import datetime

GEMINI_API_KEY = "AIzaSyBfh9cassXz_MMYMFAZGtRxhlSccKcXQ6g"


def _extract_from_image_gemini(image_path: str) -> str:
    try:
        from google import genai
        import PIL.Image
        client = genai.Client(api_key=GEMINI_API_KEY)
        img = PIL.Image.open(image_path)
        prompt = (
            "Extrae TODO el texto visible en esta imagen de factura. "
            "Devuelve exactamente el texto tal como aparece, sin resumir ni modificar."
        )
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[prompt, img]
        )
        if response.text:
            print(f"[OCR] Gemini OK: {len(response.text)} chars")
            return response.text.strip()
        return ""
    except Exception as e:
        print(f"[OCR] Gemini: {e}")
        return ""


def parse_factura_text(text: str) -> dict:
    data = {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}

    rif_patterns = [
        r'R\.I\.F[- ]?C\.I\.?:\s*(J\d{8,9})',
        r'RIF\.?\s*(J\d{8,9})',
        r'\bJ\d{8,9}\b',
    ]
    for pattern in rif_patterns:
        rif_match = re.search(pattern, text, re.IGNORECASE)
        if rif_match:
            data["rif"] = rif_match.group(1)
            print(f"[PARSE] RIF: {data['rif']}")
            break

    nro_patterns = [
        r'FACTURA\s*#\s*(\d+)',
        r'Nro:\s*FACTURA\s*#\s*(\d+)',
        r'#\s*(\d{6,10})',
    ]
    for pattern in nro_patterns:
        nro_match = re.search(pattern, text, re.IGNORECASE)
        if nro_match:
            data["nro_factura"] = nro_match.group(1)
            print(f"[PARSE] Factura: {data['nro_factura']}")
            break

    fecha_patterns = [
        r'Fecha:\s*(\d{1,2})/(\d{1,2})/(\d{4})',
        r'(\d{1,2})/(\d{1,2})/(\d{4})',
    ]
    for pattern in fecha_patterns:
        fecha_match = re.search(pattern, text, re.IGNORECASE)
        if fecha_match:
            dia, mes, anio = int(fecha_match.group(1)), int(fecha_match.group(2)), int(fecha_match.group(3))
            if 1 <= dia <= 31 and 1 <= mes <= 12 and 2020 <= anio <= 2030:
                data["fecha"] = f"{dia:02d}/{mes:02d}/{anio:04d}"
                print(f"[PARSE] Fecha: {data['fecha']}")
                break

    prov_patterns = [
        r'Proveedor:\s*(.+?)(?:\s*(?:Direcci|RIF|Tel[éo]f|Fecha|Vence|Cod))',
    ]
    for pattern in prov_patterns:
        prov_match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        if prov_match:
            prov = prov_match.group(1).strip()[:60]
            if ',' in prov:
                prov = prov.rsplit(',', 1)[0] + ','
            if len(prov) > 2:
                data["proveedor"] = re.sub(r'\s+', ' ', prov)
                print(f"[PARSE] Proveedor: {data['proveedor']}")
                break

    if not data["proveedor"]:
        for line in text.split('\n')[:5]:
            line = line.strip()
            if len(line) > 5 and (',' in line or 'C.A.' in line.upper()):
                data["proveedor"] = line
                print(f"[PARSE] Proveedor fallback: {line}")
                break

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

    full_text = ""

    # 1. Gemini (primario)
    full_text = _extract_from_image_gemini(image_path)

    # 2. Tesseract fallback
    if not full_text.strip():
        try:
            import pytesseract
            from PIL import Image
            print("[OCR] Tesseract...")
            img = Image.open(image_path)
            full_text = pytesseract.image_to_string(img, lang='spa', config=r'--oem 3 --psm 6')
            if full_text.strip():
                print(f"[OCR] Tesseract OK: {len(full_text)} chars")
        except ImportError:
            print("[OCR] Tesseract no instalado")
        except Exception as e:
            print(f"[OCR] Tesseract: {e}")

    # 3. EasyOCR fallback
    if not full_text.strip():
        try:
            reader = _get_easyocr_reader()
            if reader:
                print("[OCR] EasyOCR...")
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
