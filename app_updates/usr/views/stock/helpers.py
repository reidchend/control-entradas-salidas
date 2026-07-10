import flet as ft
from usr.theme import get_colors

def get_safe_colors(page):
    if not page:
        return get_colors(None)
    return get_colors(page)

def get_mapped_color(page, color_name):
    mapping = get_color_mapping(page)
    return mapping.get(color_name, get_safe_colors(page)['text_primary'])

def get_color_mapping(page):
    colors = get_safe_colors(page)
    return {
        'GREY_300': colors['text_hint'],
        'GREY_400': colors['text_secondary'],
        'GREY_500': colors['text_secondary'],
        'GREY_600': colors['text_secondary'],
        'GREY_200': colors['border'],
        'GREY_50': colors['bg'],
        'WHITE': colors['white'],
        'BLUE_GREY_900': colors['text_primary'],
        'BLUE_GREY_800': colors['text_primary'],
        'BLUE_GREY_700': colors['text_primary'],
        'BLUE_GREY_500': colors['text_secondary'],
        'BLUE_GREY_400': colors['text_secondary'],
        'BLUE_50': colors.get('blue_50', colors['bg']),
        'BLUE_400': colors['accent'],
        'BLUE_600': colors['accent'],
        'BLUE_700': colors['accent'],
        'GREEN_50': colors.get('green_50', colors['bg']),
        'GREEN_800': colors['success'],
        'GREEN_700': colors['success'],
        'GREEN_600': colors['success'],
        'ORANGE_50': colors.get('orange_50', colors['bg']),
        'ORANGE_200': colors['border'],
        'ORANGE_600': colors['warning'],
        'ORANGE_700': colors['warning'],
        'ORANGE_800': colors['warning'],
        'RED_600': colors['error'],
        'RED_700': colors['error'],
    }
