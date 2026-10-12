#!/usr/bin/env python3

import argparse
import os
import re
import shlex
import subprocess
import sys
import xml.etree.ElementTree as ET


VERBOSE = os.environ.get('VERBOSE', '').strip().lower() not in ('', '0', 'false', 'off')
COLOR_MODE = 'auto'
RED = 31
BLUE = 34

def print_colored(message, color):
    if COLOR_MODE != 'auto':
        use_color = COLOR_MODE == 'on'
    elif os.environ.get('NO_COLOR'):
        use_color = False
    elif os.environ.get('FORCE_COLOR'):
        use_color = os.environ['FORCE_COLOR'] != '0'
    else:
        use_color = sys.stdout.isatty()
    print(f'\033[{color}m{message}\033[0m' if use_color else message)

def print_error(message):
    print_colored(message, RED)

def adb(*args):
    command =  ['adb', 'shell', *args]
    if VERBOSE:
        print(shlex.join(command))
    return subprocess.check_output(command, text=True)

def ui():
    adb('uiautomator', 'dump', '/sdcard/rotator-window.xml')
    xml = adb('cat', '/sdcard/rotator-window.xml')
    return ET.fromstring(xml[xml.index('<?xml'):])

def find(root, name):
    return next((node for node in root.iter('node') if node.get('resource-id') == 'info.fekir.rotator:id/' + name), None)

def bounds(node):
    assert node is not None, 'Required controll missing'
    return list(map(int, re.findall(r'\d+', node.get('bounds'))))

def tap(node):
    left, top,right, bottom = bounds(node)
    adb('input', 'tap', str((left+right) // 2), str((top+bottom)//2))

def notification_tap(name):
    adb('cmd', 'statusbar', 'expand-notifications')

    root = ui()
    target = find(root,name)
    if target is None:
        left, top,right, bottom = bounds(find(root, 'btn_portrait'))
        center_x = (left+right)//2
        center_y = (top+bottom)//2
        adb('input', 'swipe', str(center_x), str(center_y), str(center_x), str(center_y+300), '300')
        target = find(ui(), name)
    tap(target)
    ui()

def display_state():
    override = next(line for line in adb('dumpsys', 'display').splitlines() if 'mOverrideDisplayInfo=' in line)
    width, height = map(int, re.search(r'real (\d+) x (\d+)', override).groups())
    rotation = int(re.search(r'rotation (\d+)', override).group(1))
    return width, height, rotation

def main():
    original_rotation = int(adb('settings', 'get', 'system', 'user_rotation').strip())
    original_auto = int(adb('settings', 'get', 'system', 'accelerometer_rotation').strip())
    width, height, current_rotation = display_state()
    natural_landscape = width > height if current_rotation % 2 == 0 else height > width
    portrait_rotation = 3 if natural_landscape else 0
    landscape_rotation = 0 if natural_landscape else 1
    rotation_cases = [
        ('btn_portrait', portrait_rotation, True),
        ('btn_portrait_r', (portrait_rotation+2)%4, True),
        ('btn_landscape_r', (landscape_rotation+2)%4, False),
        ('btn_landscape', landscape_rotation, False)
    ]
    rotation_buttons = {rotation: name for name, rotation, portrait in rotation_cases}
    try:
        adb('cmd', 'statusbar', 'collapse')
        adb('input','keyevent','3')

        adb('am', 'start', '-n', 'info.fekir.rotator/.MainActivity')
        tap(find(ui(), 'start_button'))
        # note: hardcoded from zebra?
        for name, expected_rotation, portrait in rotation_cases:
            notification_tap(name)
            rotation = int(adb('settings', 'get', 'system', 'user_rotation').strip())
            auto = int(adb('settings', 'get', 'system', 'accelerometer_rotation').strip())
            width, height, actual_rotation = display_state()
            assert rotation == expected_rotation, (name, rotation, expected_rotation)
            assert actual_rotation == expected_rotation, (name, actual_rotation, expected_rotation)
            assert auto == 0, (name, auto)
            assert (height > width) == portrait, (name, width, height)
            print(f'Pass {name}: rotation={rotation}, display={width}x{height}, auto={auto}')
        notification_tap('btn_auto')
        assert int(adb('settings', 'get', 'system', 'accelerometer_rotation').strip()) == 1
    except KeyboardInterrupt:
        print_error("Test interrupted by user")
        raise SystemExit(2)
    except Exception as error:
        print_error(f'Test failed: {error}')
        raise SystemExit(1)
    finally:
        print_colored("Restore original rotation settings", BLUE)
        try:
            notification_tap('btn_auto' if original_auto else rotation_buttons[original_rotation])
            adb('settings', 'put', 'system', 'user_rotation', str(original_rotation))
            adb('settings', 'put', 'system', 'accelerometer_rotation', str(original_auto))
            restored_rotation = int(adb('settings', 'get', 'system', 'user_rotation').strip())
            restored_auto = int(adb('settings', 'get', 'system', 'accelerometer_rotation').strip())
            assert restored_rotation == original_rotation, (restored_rotation, original_rotation)
            assert restored_auto == original_auto, (restored_auto, original_auto)
        finally:
            adb('cmd', 'statusbar', 'collapse')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Test rotator on attached device')
    parser.add_argument('--verbose', action='store_true', default=VERBOSE, help='verbose output during test')
    parser.add_argument('--color', choices=('auto', 'on', 'off'), default=COLOR_MODE, help='configure colorized output')
    options = parser.parse_args()
    VERBOSE = options.verbose
    COLOR_MODE = options.color
    try:
        main()
    except KeyboardInterrupt:
        print_error('Test interrupted by user')
        raise SystemExit(2)
    except Exception as error:
        print_error(f'Test failed: {error}')
        raise SystemExit(1)
