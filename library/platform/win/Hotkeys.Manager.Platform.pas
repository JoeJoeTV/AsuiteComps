{
Copyright (C) 2006-2020 Matteo Salvi

Website: http://www.salvadorsoftware.com/

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

---

With some original code by Codebot (Cross Pascal Library) - https://github.com/sysrpl/Cross.Codebot/

}

unit Hotkeys.Manager.Platform;

{$MODE DelphiUnicode}

interface

uses
  windows, Dialogs, LCLProc, Hotkeys.Manager, Hotkeys.ShortcutEx, Classes, SysUtils;

type

  { TWin32HotkeyManager }

  TWin32HotkeyManager = class(TBaseHotkeyManager)
  private
    FWindowClassAtom: ATOM;
    FWindowClassInfo: WNDCLASSEX;

    function CreateAppWindow: boolean;
    function RegisterWindowClass: boolean;
    procedure SeparateHotKey(HotKey: Cardinal; var Modifiers, Key: Word);
  protected
    function DoRegister(Shortcut: TShortCutEx): Boolean; override;
    function DoUnregister(Shortcut: TShortCutEx): Boolean; override;
  public
    constructor Create; override;
    destructor Destroy; override;

    function IsHotkeyAvailable(Shortcut: TShortCut): Boolean; override;
  end;

{ Returns the global hotkey manager instance }
function HotkeyManager: TBaseHotkeyManager;

var
  HWindow: HWND;

const
  WinClassName: string = 'TWin32HotkeyApp';
  HotKeyAtomPrefix: string = 'TWin32Hotkey';

implementation

function HotkeyManager: TBaseHotkeyManager;
begin
  if InternalManager = nil then
    InternalManager := TWin32HotkeyManager.Create;

  Result := TBaseHotkeyManager(InternalManager);
end;

function WinProc(hw: HWND; uMsg: UINT; wp: WPARAM; lp: LPARAM): LRESULT;
  stdcall; export;
var
  Capture: TWin32HotkeyManager;
  I: Integer;
  H: TShortcutEx;
begin
  Result := 0;
  case uMsg of
    WM_HOTKEY:
      begin
        Capture := TWin32HotkeyManager(GetWindowLongPtr(HWindow, GWL_USERDATA));
        I := Capture.FindHotkeyByIndex(Longint(wp));

        if I > -1 then
        begin
          H := Capture[I];
          if Assigned(H.Notify) then
            H.Notify(Capture, H);
        end;
      end
  else
    Result := DefWindowProc(hw, uMsg, wp, lp);
  end;
end;

{ TWin32HotkeyManager }

procedure TWin32HotkeyManager.SeparateHotKey(HotKey: Cardinal; var Modifiers, Key: Word);
// Separate key and modifiers, so they can be used with RegisterHotKey
const                       
  VK2_META    =  16;
  VK2_SHIFT   =  32;
  VK2_CONTROL =  64;
  VK2_ALT     = 128;
  VK2_WIN     = 256;
var
  Virtuals: Integer;
  V: Word;
  x: Word;
begin
  Key := Byte(HotKey);
  x := HotKey shr 8;
  Virtuals := x;
  V := 0;     
  if (Virtuals and VK2_META) <> 0 then
    Inc(V, MOD_WIN);
  if (Virtuals and VK2_WIN) <> 0 then
    Inc(V, MOD_WIN);
  if (Virtuals and VK2_ALT) <> 0 then
    Inc(V, MOD_ALT);
  if (Virtuals and VK2_CONTROL) <> 0 then
    Inc(V, MOD_CONTROL);
  if (Virtuals and VK2_SHIFT) <> 0 then
    Inc(V, MOD_SHIFT);
  Modifiers := V;
end;

function TWin32HotkeyManager.RegisterWindowClass: boolean;
begin
  FWindowClassInfo.cbSize := sizeof(FWindowClassInfo);
  FWindowClassInfo.Style := 0;
  FWindowClassInfo.lpfnWndProc := @WinProc;
  FWindowClassInfo.cbClsExtra := 0;
  FWindowClassInfo.cbWndExtra := 0;
  FWindowClassInfo.hInstance := hInstance;
  FWindowClassInfo.hIcon := 0;
  FWindowClassInfo.hCursor := 0;
  FWindowClassInfo.hbrBackground := 0;
  FWindowClassInfo.lpszMenuName := nil;
  FWindowClassInfo.lpszClassName := PAnsiChar(WinClassName);
  FWindowClassInfo.hIconSm := 0;
  FWindowClassAtom := RegisterClassEx(FWindowClassInfo);
  Result := FWindowClassAtom <> 0;
end;

function TWin32HotkeyManager.CreateAppWindow: boolean;
begin
  Result := false;

  if not RegisterWindowClass then
    exit;

  HWindow := CreateWindowEx(WS_EX_NOACTIVATE or WS_EX_TRANSPARENT,
    PAnsiChar(WinClassName), PAnsiChar(WinClassName), Ws_popup or WS_CLIPSIBLINGS, 0, 0,
    0, 0, 0, 0, hInstance, nil);

  if HWindow <> 0 then
  begin
    ShowWindow(HWindow, SW_HIDE);
    SetWindowLongPtr(HWindow, GWL_USERDATA, PtrInt(Self));

    UpdateWindow(HWindow);
    Result := True;
    exit;
  end;
end;

function TWin32HotkeyManager.DoRegister(Shortcut: TShortCutEx): Boolean;
var
  Key, Modifiers: Word;
  id: Integer;
begin
  SeparateHotKey(Shortcut.SimpleShortcut, Modifiers, Key);

  id := GlobalAddAtomW(PChar(HotKeyAtomPrefix + IntToStr(Shortcut.SimpleShortcut)));
  Result := RegisterHotKey(HWindow, Longint(id), Modifiers, Key);

  if Result then
    Shortcut.Index := id;
end;

function TWin32HotkeyManager.DoUnregister(Shortcut: TShortCutEx): Boolean;
var
  I, Index: Integer;
begin                                
  I := FindHotkey(Shortcut.SimpleShortcut);
  Index := Self[I].Index;

  Result := UnRegisterHotkey(HWindow, Longint(Index));
  GlobalDeleteAtom(Index);
end;

constructor TWin32HotkeyManager.Create;
begin
  inherited Create;    

  CreateAppWindow;
end;

destructor TWin32HotkeyManager.Destroy;
begin             
  DestroyWindow(HWindow);

  inherited Destroy;
end;

function TWin32HotkeyManager.IsHotkeyAvailable(Shortcut: TShortCut): Boolean;
var
  Modifiers, Key: Word;
  WasRegistered: boolean;
  ATOM: Word;
begin
  Key := 0;
  Modifiers := 0;
  ATOM := GlobalAddAtomW(PChar(HotKeyAtomPrefix + IntToStr(Shortcut)));
  SeparateHotKey(Shortcut, Modifiers, Key);

  Result := RegisterHotKey(HWindow, ATOM, Modifiers, Key);
  if Result then
    UnRegisterHotkey(HWindow, ATOM);

  GlobalDeleteAtom(ATOM);
end;

end.
