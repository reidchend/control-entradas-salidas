from usr.theme import get_colors


def _colors(page):
    return get_colors(page)


def _c(page, color_name):
    colors = _colors(page)
    mapping = {
        'WHITE': colors['white'],
        'GREY_300': colors['text_hint'],
        'GREY_400': colors['text_secondary'],
        'GREY_500': colors['text_secondary'],
        'GREY_600': colors['text_secondary'],
        'GREY_50': colors['bg'],
        'BLUE_GREY_900': colors['text_primary'],
        'BLUE_GREY_800': colors['text_primary'],
        'BLUE_600': colors['accent'],
        'BLUE_700': colors['accent'],
        'GREEN_600': colors['success'],
        'GREEN_700': colors['success'],
        'RED_600': colors['error'],
        'RED_700': colors['error'],
        'ORANGE_600': colors['warning'],
        'ORANGE_700': colors['warning'],
    }
    return mapping.get(color_name, colors['text_primary'])


def get_safe_colors(page):
    if page:
        c = _colors(page)
        if c:
            return c
    return {
        'white': '#FFFFFF', 'bg': '#1A1A1A', 'surface': '#2D2D2D',
        'card': '#333333', 'card_hover': '#3A3A3A', 'border': '#404040',
        'accent': '#7C4DFF', 'accent_dark': '#651FFF',
        'success': '#4CAF50', 'error': '#F44336', 'warning': '#FF9800',
        'text_primary': '#FFFFFF', 'text_secondary': '#B0B0B0',
        'text_hint': '#757575',
        'input_border': '#555555',
    }


def trigger_sync(view):
    try:
        from usr.database.sync import get_sync_manager
        sync_mgr = get_sync_manager()
        if sync_mgr and sync_mgr.check_connection():
            import threading
            thread = threading.Thread(target=sync_mgr._process_sync_queue, daemon=True)
            thread.start()
    except Exception as e:
        print(f"[SYNC] Error al activar sync inmediato: {e}")
