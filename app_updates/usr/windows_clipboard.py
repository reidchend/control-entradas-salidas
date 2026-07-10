"""
Módulo para leer imágenes del portapapeles de Windows.
Usa ctypes puro - sin dependencias externas.
"""
import os
import tempfile
from ctypes import windll, sizeof, c_void_p, c_wchar_p, POINTER, byref, Structure
from ctypes.wintypes import BYTE, WORD, DWORD, HBITMAP, HANDLE, BOOL, LPCWSTR


class BITMAPINFOHEADER(Structure):
    _fields_ = [
        ('biSize', DWORD),
        ('biWidth', DWORD),
        ('biHeight', DWORD),
        ('biPlanes', WORD),
        ('biBitCount', WORD),
        ('biCompression', DWORD),
        ('biSizeImage', DWORD),
        ('biXPelsPerMeter', DWORD),
        ('biYPelsPerMeter', DWORD),
        ('biClrUsed', DWORD),
        ('biClrImportant', DWORD),
    ]


# Constantes de Windows
CF_DIB = 8
GMEM_MOVEABLE = 0x0002


# Funciones de Windows
user32 = windll.user32
gdi32 = windll.gdi32
kernel32 = windll.kernel32


def get_clipboard_image():
    """
    Lee una imagen del portapapeles de Windows.
    
    Returns:
        str: Ruta al archivo temporal con la imagen, o None si no hay imagen.
    """
    try:
        # Abrir portapapeles
        user32.OpenClipboard(None)
        
        try:
            # Verificar si hay imagen en el portapapeles (CF_DIB = 8)
            if not user32.IsClipboardFormatAvailable(CF_DIB):
                print("[CLIPBOARD] No hay imagen en el portapapeles (formato CF_DIB)")
                return None
            
            # Obtener el handle del bitmap
            h_bmp = user32.GetClipboardData(CF_DIB)
            if not h_bmp:
                print("[CLIPBOARD] No se pudo obtener el handle del bitmap")
                return None
            
            print(f"[CLIPBOARD] Handle del bitmap: {h_bmp}")
            
            # Convertir el bitmap a formato usable
            # Primero necesitamos obtener la información del bitmap
            bmp_info = windll.gdi32.GetObjectW(h_bmp, 0, None)
            if bmp_info == 0:
                print("[CLIPBOARD] Error al obtener información del bitmap")
                return None
            
            # Obtener dimensiones del bitmap
            bi = BITMAPINFOHEADER()
            # Usar GetDIBits para obtener la información
            success = windll.gdi32.GetDIBits(
                windll.gdi32.GetDC(None),
                h_bmp,
                0,  # start scan
                0,  # max scan
                None,  # buffer
                byref(bi),
                0,  # usage (DIB_RGB_COLORS)
            )
            
            if success == 0:
                # Método alternativo - usar PIL para convertir
                print("[CLIPBOARD] Intentando método alternatif con PIL")
                return _get_clipboard_with_pil()
            
            print(f"[CLIPBOARD] Bitmap: {bi.biWidth}x{bi.biHeight}, {bi.biBitCount} bpp")
            
            # Crear archivo temporal
            temp_dir = tempfile.gettempdir()
            output_path = os.path.join(temp_dir, "clipboard_image.png")
            
            # Guardar la imagen usando PIL
            try:
                from PIL import Image
                import numpy as np
                
                # Obtener los bits del bitmap
                buf_size = bi.biWidth * bi.biHeight * 4  # 4 bytes por pixel (32 bpp)
                buf = (c_void_p * buf_size)()
                
                bits = windll.gdi32.GetDIBits(
                    windll.gdi32.GetDC(None),
                    h_bmp,
                    0,
                    bi.biHeight,
                    byref(buf),
                    byref(bi),
                    0
                )
                
                if bits:
                    # Crear imagen desde buffer
                    # Invertir verticalmente (bitmaps están invertidos)
                    img_array = np.frombuffer(buf, dtype=np.uint8)
                    img_array = img_array.reshape((bi.biHeight, bi.biWidth, 4))
                    img_array = np.flipud(img_array)
                    
                    # Crear imagen y guardar
                    if bi.biBitCount == 32:
                        img = Image.fromarray(img_array[:, :, :3], 'RGB')
                    elif bi.biBitCount == 24:
                        img = Image.fromarray(img_array[:, :, :3], 'RGB')
                    else:
                        print(f"[CLIPBOARD] Profundidad de color no soportada: {bi.biBitCount}")
                        return None
                    
                    img.save(output_path, 'PNG')
                    print(f"[CLIPBOARD] Imagen guardada en: {output_path}")
                    return output_path
                else:
                    return _get_clipboard_with_pil()
                    
            except ImportError:
                print("[CLIPBOARD] PIL no está disponible, intentando otro método")
                return _get_clipboard_with_pil()
                
        finally:
            user32.CloseClipboard()
    
    except Exception as e:
        import traceback
        print(f"[CLIPBOARD] Error: {e}")
        traceback.print_exc()
        return None


def _get_clipboard_with_pil():
    """
    Método alternativo usando PIL para obtener imagen del portapapeles.
    Necesita PIL o pillow instalado.
    """
    try:
        from PIL import Image
        import io
        
        # Intentar obtener imagen usando PIL
        # Este método funciona si hay una imagen en el portapapeles
        # que PIL pueda leer
        
        # Usar el portapapeles de Windows a través de Image
        img = Image.open("clipboard:")
        
        # Guardar en archivo temporal
        temp_dir = tempfile.gettempdir()
        output_path = os.path.join(temp_dir, "clipboard_image.png")
        
        # Convertir a RGB si es necesario
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        img.save(output_path, 'PNG')
        print(f"[CLIPBOARD] Imagen guardada (PIL) en: {output_path}")
        
        return output_path
        
    except Exception as e:
        print(f"[CLIPBOARD] Error con método PIL: {e}")
        
        # Último intento: usar ventana de portapapeles
        try:
            # Intentar con win32api directamente
            import subprocess
            
            # Usar herramienta de línea de comandos
            #尝试使用 PowerShell para guardar portapapeles
            result = subprocess.run([
                'powershell', '-Command', 
                'Add-Type -AssemblyName System.Windows.Forms; '
                '$img = [System.Windows.Forms.Clipboard]::GetImage; '
                'if ($img) { $img.Save("' + tempfile.gettempdir().replace('\\', '\\\\') + '\\\\clipboard_powershell.png", [System.Drawing.Imaging.ImageFormat]::Png) }'
            ], capture_output=True, timeout=5)
            
            if result.returncode == 0:
                output_path = os.path.join(tempfile.gettempdir(), 'clipboard_powershell.png')
                if os.path.exists(output_path):
                    print(f"[CLIPBOARD] Imagen guardada (PowerShell) en: {output_path}")
                    return output_path
                    
        except Exception as ps_error:
            print(f"[CLIPBOARD] Error con PowerShell: {ps_error}")
        
        return None


def get_windows_clipboard():
    """
    Wrapper que intenta múltiples métodos para obtener imagen del portapapeles.
    
    Returns:
        str: Ruta al archivo temporal, o None si no hay imagen.
    """
    # Método 1: Intentar con Windows API
    result = get_clipboard_image()
    if result and os.path.exists(result):
        return result
    
    # Método 2: Intentar con PIL
    result = _get_clipboard_with_pil()
    if result and os.path.exists(result):
        return result
    
    return None


if __name__ == "__main__":
    # Prueba del módulo
    print("=== Prueba de portapapeles de Windows ===")
    result = get_windows_clipboard()
    if result:
        print(f"✅ Imagen obtenida: {result}")
    else:
        print("❌ No se pudo obtener imagen del portapapeles")