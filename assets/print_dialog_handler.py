import sys
import traceback
from pywinauto import Application
from pywinauto.findwindows import find_windows
import time

def click_ok_in_print_dialog():
    try:
        print_windows = find_windows(title="Print Setup", class_name="#32770", enabled_only=True, visible_only=True)
        
        if not print_windows:
            return False
            
        window_handle = print_windows[0]
        app = Application().connect(handle=window_handle)
        print_dialog = app.window(handle=window_handle)
        
        expected_controls = ["Printer", "Paper", "Orientation"]
        found_controls = [child.window_text() for child in print_dialog.children()]
        
        if not all(control in found_controls for control in expected_controls):
            print("Found window is not the correct Print Setup dialog")
            return False
            
        print_dialog.set_focus()
        
        ok_button = print_dialog.child_window(title="OK", class_name="Button")
        if ok_button.exists() and ok_button.is_visible() and ok_button.is_enabled():
            ok_button.click_input()
            return True
        else:
            return False
            
    except Exception as e:
        print(f"Error: {str(e)}")
        print(traceback.format_exc())
        return False

if __name__ == "__main__":
    while True:
        if click_ok_in_print_dialog():
            time.sleep(0.5)
        else:
            time.sleep(0.1) 