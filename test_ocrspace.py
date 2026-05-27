r"""
Prueba del API de OCR.SPACE Free OCR API
Gratuito hasta 500 req/dia, 25 req/hour sin API key.
Con API key (gratuita): hasta 1000 req/dia.

API Key (tuya): K86411242588957
Base URL: https://api.ocr.space/parse/image

Uso:
    python test_ocrspace.py <ruta_imagen>
    python test_ocrspace.py "factura.png"
"""
import sys
import base64
import os
import json
import requests

API_KEY = "K86411242588957"
API_URL = "https://api.ocr.space/parse/image"


def ocr_image_file(image_path: str, api_key: str = API_KEY) -> dict:
    """Envía una imagen al API de OCR.SPACE y devuelve el resultado."""
    if not os.path.exists(image_path):
        return {"error": f"Archivo no encontrado: {image_path}"}

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

    headers = {
        'apikey': api_key,
    }

    print(f"[OCR.SPACE] Enviando {image_path}...")
    response = requests.post(
        'https://api.ocr.space/parse/image',
        data=payload,
        headers=headers,
        timeout=30
    )

    result = response.json()
    print(f"[OCR.SPACE] Status: {response.status_code}, IsError: {result.get('IsErroredOnProcessing')}")

    if result.get("IsErroredOnProcessing"):
        return {"error": result.get("ErrorMessage", "Error desconocido")}

    parsed_results = result.get("ParsedResults", [])
    if not parsed_results:
        return {"error": "Sin texto detectado", "raw": result}

    full_text = "\n".join([
        r.get("ParsedText", "")
        for r in parsed_results
    ])

    return {
        "text": full_text.strip(),
        "confidence": parsed_results[0].get("TextOverlay", {}).get("MeanConfidence", 0),
        "raw": result,
    }


def ocr_url(image_url: str, api_key: str = API_KEY) -> dict:
    """Descarga una imagen desde URL y la envía al API de OCR.SPACE."""
    print(f"[OCR.SPACE] Descargando {image_url}...")
    try:
        img_response = requests.get(image_url, timeout=15)
        img_response.raise_for_status()
        img_data = base64.b64encode(img_response.content).decode('utf-8')
    except Exception as e:
        return {"error": f"No se pudo descargar imagen: {e}"}

    payload = {
        'base64Image': f"data:image/png;base64,{img_data}",
        'language': 'spa',
        'isOverlayRequired': 'false',
        'detectOrientation': 'true',
        'scale': 'true',
        'OCREngine': 2,
    }

    headers = {'apikey': api_key}

    print(f"[OCR.SPACE] Enviando imagen desde URL...")
    response = requests.post(
        'https://api.ocr.space/parse/image',
        data=payload,
        headers=headers,
        timeout=30
    )

    result = response.json()
    print(f"[OCR.SPACE] Status: {response.status_code}, IsError: {result.get('IsErroredOnProcessing')}")

    if result.get("IsErroredOnProcessing"):
        return {"error": result.get("ErrorMessage", ["Error desconocido"])}

    parsed_results = result.get("ParsedResults", [])
    if not parsed_results:
        return {"error": "Sin texto detectado", "raw": result}

    full_text = "\n".join([
        r.get("ParsedText", "")
        for r in parsed_results
    ])

    return {
        "text": full_text.strip(),
        "confidence": parsed_results[0].get("TextOverlay", {}).get("MeanConfidence", 0),
        "raw": result,
    }


def main():
    if len(sys.argv) < 2:
        print("Uso: python test_ocrspace.py <ruta_imagen>")
        print("   python test_ocrspace.py https://ejemplo.com/factura.jpg  (por URL)")
        sys.exit(1)

    arg = sys.argv[1]

    if arg.startswith('http://') or arg.startswith('https://'):
        result = ocr_url(arg)
    else:
        result = ocr_image_file(arg)

    if "error" in result:
        print(f"\n[X] Error: {result['error']}")
        if "raw" in result:
            print(f"    Detalle: {result.get('raw')}")
        sys.exit(1)

    text = result['text']
    conf = result.get('confidence', 0)
    print(f"\n[OK] Texto extraido (confianza: {conf:.1%}):")
    print("-" * 60)
    print(text)
    print("-" * 60)
    print(f"\nTotal: {len(text)} caracteres")

    from usr.ocr_extractor import parse_factura_text
    datos = parse_factura_text(text)
    print(f"\nDatos parseados:")
    print(f"  Proveedor: {datos.get('proveedor', 'N/A')}")
    print(f"  RIF:       {datos.get('rif', 'N/A')}")
    print(f"  Factura:   {datos.get('nro_factura', 'N/A')}")
    print(f"  Fecha:     {datos.get('fecha', 'N/A')}")


if __name__ == "__main__":
    main()
