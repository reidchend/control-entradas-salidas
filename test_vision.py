from google import genai
import PIL.Image
import json
import sys
import os

API_KEY = "AIzaSyBfh9cassXz_MMYMFAZGtRxhlSccKcXQ6g"

MODELS = [
    "gemini-3.1-flash-lite-preview",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
]

image_path = sys.argv[1] if len(sys.argv) > 1 else ""

if not image_path:
    print("Usage: python test_vision.py <ruta_imagen>")
    print('Ej: python test_vision.py "assets/WhatsApp Image 2026-05-07 at 1.36.33 PM.jpeg"')
    sys.exit(1)

if not os.path.exists(image_path):
    print(f"ERROR: Archivo no encontrado: {image_path}")
    sys.exit(1)

prompt = (
    'Analiza este documento de recepción. No asumas que el encabezado es el proveedor y extrae los datos en formato JSON.\n\n'
    'Busca estos 4 campos:\n'
    '- proveedor: razón social del comercio que EMITE la factura\n'
    '- rif: RIF del proveedor (formato J00000000, solo números, sin guiones ni espacios)\n'
    '- nro_factura: número de factura (solo dígitos)\n'
    '- fecha: fecha en formato DD/MM/AAAA\n\n'
    'REGLAS:\n'
    '- El RIF debe ser el del PROVEEDOR, NO el de quien recibe la factura\n'
    '- Si no encuentras un dato, usa null para ese campo\n'
    '- Devuelve SOLO JSON válido, sin texto antes ni después del JSON\n\n'
    'Ejemplo de respuesta:\n'
    '{"proveedor": "DISTRIBUIDORA X, C.A.", "rif": "J308793728", "nro_factura": "000063455", "fecha": "09/05/2026"}'
)

print(f"Enviando {image_path} a Gemini...")

for model in MODELS:
    print(f"\n--- Intentando {model} ---")
    try:
        client = genai.Client(api_key=API_KEY)
        img = PIL.Image.open(image_path)
        response = client.models.generate_content(model=model, contents=[prompt, img])

        if not response.text:
            print("No se detectó texto.")
            continue

        raw = response.text.strip()
        print(f"Respuesta ({len(raw)} chars):")
        print("-" * 60)
        print(raw)
        print("-" * 60)

        for line in raw.split('\n'):
            line = line.strip()
            if line.startswith('{'):
                data = json.loads(line)
                print(f"\nDatos extraidos:")
                print(f"  Proveedor: {data.get('proveedor')}")
                print(f"  RIF: {data.get('rif')}")
                print(f"  Factura: {data.get('nro_factura')}")
                print(f"  Fecha: {data.get('fecha')}")
                break
        else:
            print("No se encontró JSON en la respuesta.")
    except Exception as e:
        err = str(e).lower()
        if "429" in err or "quota" in err or "exceeded" in err or "resource_exhausted" in err:
            print(f"Cuota agotada para {model}, probando siguiente...")
            continue
        print(f"Error: {e}")
    break
else:
    print("\nTodos los modelos agotados.")
