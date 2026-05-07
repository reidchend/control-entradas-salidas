import re
import os
from datetime import datetime


def parse_factura_text(text: str) -> dict:
    """
    Extrae datos de factura desde texto OCR.
    
    Args:
        text: Texto completo extraído de la imagen
        
    Returns:
        dict con proveedor, rif, nro_factura, fecha
    """
    data = {
        "proveedor": "",
        "rif": "",
        "nro_factura": "",
        "fecha": ""
    }
    
    # 1. Extraer RIF (formato Venezuela: J-XXXXXXXX-X o JXXXXXXXXX)
    # Patrones: J-12345678-9, G-12345678-9, E-12345678-9
    rif_match = re.search(r'([JGPE])[-]?(\d{8,9})[-]?([A-Z0-9])', text, re.IGNORECASE)
    if rif_match:
        data["rif"] = f"{rif_match.group(1)}-{rif_match.group(2)}-{rif_match.group(3)}"
    
    # 2. Extraer Número de Factura (después de # o "Factura" o "Nro")
    nro_match = re.search(r'#\s*([A-Z0-9-]+)', text, re.IGNORECASE)
    if not nro_match:
        nro_match = re.search(r'(?:Factura|Nro|Número)[:\s]*([A-Z0-9-]+)', text, re.IGNORECASE)
    if nro_match:
        data["nro_factura"] = nro_match.group(1).strip()
    
    # 3. Extraer Fecha (DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY)
    fecha_match = re.search(r'(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})', text)
    if fecha_match:
        dia = int(fecha_match.group(1))
        mes = int(fecha_match.group(2))
        anio = int(fecha_match.group(3))
        # Corregir año si es solo 2 dígitos
        if anio < 100:
            anio += 2000
        # Validar rango razonable
        if 1 <= dia <= 31 and 1 <= mes <= 12 and 2020 <= anio <= 2030:
            data["fecha"] = f"{dia:02d}/{mes:02d}/{anio:04d}"
    
    # 4. Extraer Proveedor
    # Buscar entre "Proveedor:" y "Dirección" o "RIF" o "Teléfono"
    prov_match = re.search(
        r'Proveedor:\s*(.+?)(?:\s*(?:Dirección|RIF|Teléfono|Telf|Fecha))',
        text, re.DOTALL | re.IGNORECASE
    )
    if prov_match:
        data["proveedor"] = prov_match.group(1).strip()
        # Limpiar saltos de línea多余
        data["proveedor"] = re.sub(r'\s+', ' ', data["proveedor"])
    
    # Si no se encontró proveedor, intentar primera línea con letras
    if not data["proveedor"]:
        for line in text.split('\n')[:5]:
            if len(line.strip()) > 3 and re.match(r'^[A-Za-z]', line):
                data["proveedor"] = line.strip()
                break
    
    return data


def preprocess_image(image_path: str) -> str:
    """
    Pre-procesa imagen para mejorar OCR.
    Requiere opencv-python instalado.
    """
    try:
        import cv2
        
        if not os.path.exists(image_path):
            return image_path
        
        # Cargar imagen
        img = cv2.imread(image_path)
        if img is None:
            return image_path
        
        # Convertir a escala de grises
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Aplicar thresholding Otsu para mejorar contraste
        _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # Guardar imagen procesada
        processed_path = image_path.replace('.png', '_processed.png').replace('.jpg', '_processed.jpg')
        cv2.imwrite(processed_path, thresh)
        
        return processed_path
    except ImportError:
        # Si no hay opencv, devolver imagen original
        return image_path
    except Exception as e:
        print(f"[OCR PREPROCESS] Error: {e}")
        return image_path


def extract_from_image(image_path: str, use_preprocessing: bool = True) -> dict:
    """
    Extrae datos de factura desde imagen usando OCR.
    Requiere PaddleOCR instalado.
    
    Args:
        image_path: Ruta a la imagen
        use_preprocessing: Aplicar pre-procesamiento de imagen
    
    Returns:
        dict con proveedor, rif, nro_factura, fecha
    """
    if not image_path:
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}
    
    # Pre-procesar imagen si se solicita
    if use_preprocessing:
        try:
            image_path = preprocess_image(image_path)
        except Exception as e:
            print(f"[OCR PREPROCESS] Error: {e}")
    
    full_text = ""
    
    # Intentar PaddleOCR
    try:
        from paddleocr import PaddleOCR
        
        print(f"[OCR] Loading PaddleOCR...")
        ocr = PaddleOCR(use_angle_cls=True, lang='es')
        result = ocr.ocr(image_path, cls=True)
        
        if result and result[0]:
            for line in result[0]:
                if line and len(line) > 1 and len(line[1]) > 1:
                    text_line = line[1][0]
                    full_text += text_line + " "
                    print(f"[OCR] Line: {text_line}")
        
        print(f"[OCR] Total text extracted: {len(full_text))} chars")
        print(f"[OCR] First 500 chars: {full_text[:500]}")
        
    except ImportError:
        print("[OCR] PaddleOCR no instalado.")
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}
    except Exception as e:
        print(f"[OCR ERROR] {e}")
        return {"proveedor": "", "rif": "", "nro_factura": "", "fecha": ""}
    
    # Limpiar texto
    full_text = full_text.strip()
    
    # Parsear datos
    return parse_factura_text(full_text)


def check_proveedor_exists(proveedor_nombre: str, rif: str = "") -> dict:
    """
    Verifica si el proveedor existe en la base de datos.
    
    Args:
        proveedor_nombre: Nombre del proveedor
        rif: RIF del proveedor (opcional)
        
    Returns:
        dict con existe (bool), id, nombre, rif
    """
    from usr.database.base import get_db_adaptive
    from usr.models import Proveedor
    
    db = next(get_db_adaptive())
    
    # Buscar por nombre o RIF
    query = db.query(Proveedor)
    
    result = {
        "existe": False,
        "id": None,
        "nombre": "",
        "rif": ""
    }
    
    # Primero buscar por nombre
    prov = query.filter(Proveedor.nombre == proveedor_nombre).first()
    if prov:
        result = {
            "existe": True,
            "id": prov.id,
            "nombre": prov.nombre,
            "rif": prov.rif or ""
        }
    elif rif:
        # Buscar por RIF
        prov = query.filter(Proveedor.rif == rif).first()
        if prov:
            result = {
                "existe": True,
                "id": prov.id,
                "nombre": prov.nombre,
                "rif": prov.rif or ""
            }
    
    return result