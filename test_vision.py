from google import genai
import PIL.Image
import sys
import os

API_KEY = "AIzaSyBfh9cassXz_MMYMFAZGtRxhlSccKcXQ6g"

image_path = sys.argv[1] if len(sys.argv) > 1 else ""

if not image_path:
    print("Usage: python test_vision.py <ruta_imagen>")
    print('Ej: python test_vision.py "assets/WhatsApp Image 2026-05-07 at 1.36.33 PM.jpeg"')
    sys.exit(1)

if not os.path.exists(image_path):
    print(f"ERROR: Archivo no encontrado: {image_path}")
    sys.exit(1)

print(f"Enviando {image_path} a Gemini...")

client = genai.Client(api_key=API_KEY)
img = PIL.Image.open(image_path)

prompt = (
    "Extrae TODO el texto visible en esta imagen de factura. "
    "Devuelve exactamente el texto tal como aparece, sin resumir ni modificar."
)

response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=[prompt, img]
)

if not response.text:
    print("No se detectó texto en la imagen.")
    sys.exit(0)

full_text = response.text.strip()
print(f"\nTexto detectado ({len(full_text)} chars):")
print("-" * 60)
print(full_text)
print("-" * 60)

from usr.ocr_extractor import parse_factura_text
result = parse_factura_text(full_text)
print(f"\nDatos extraídos: {result}")
