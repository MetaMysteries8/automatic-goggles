#include "shared_state.h"
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cwchar>

using namespace vrkbd;

namespace {

Device selected = Device::Head;
Mapping mapping;

bool Key(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

void Move(PoseState& p, double dt) {
    const double speed = (Key(VK_SHIFT) ? 1.5 : 0.45) * dt;
    const double rot = (Key(VK_SHIFT) ? 2.2 : 1.2) * dt;
    const double sy = std::sin(p.yaw), cy = std::cos(p.yaw);
    double f = 0, r = 0, u = 0;
    if (Key('W')) f += speed; if (Key('S')) f -= speed;
    if (Key('D')) r += speed; if (Key('A')) r -= speed;
    if (Key('E')) u += speed; if (Key('Q')) u -= speed;
    p.x += r * cy + f * sy;
    p.z += -f * cy + r * sy;
    p.y += u;
    if (Key(VK_LEFT)) p.yaw += rot;
    if (Key(VK_RIGHT)) p.yaw -= rot;
    if (Key(VK_UP)) p.pitch += rot;
    if (Key(VK_DOWN)) p.pitch -= rot;
    if (Key('Z')) p.roll += rot;
    if (Key('X')) p.roll -= rot;
}

void ResetSelected() {
    if (!mapping.state) return;
    if (selected == Device::Head) mapping.state->head = {0.0,1.65,0.0,0.0,0.0,0.0};
    if (selected == Device::Left) mapping.state->left.pose = {-0.25,1.30,-0.35,0.0,0.0,0.0};
    if (selected == Device::Right) mapping.state->right.pose = {0.25,1.30,-0.35,0.0,0.0,0.0};
}

void Paint(HWND hwnd) {
    PAINTSTRUCT ps; HDC dc = BeginPaint(hwnd, &ps);
    RECT r; GetClientRect(hwnd, &r);
    FillRect(dc, &r, (HBRUSH)(COLOR_WINDOW+1));
    SetBkMode(dc, TRANSPARENT);
    HFONT font=(HFONT)GetStockObject(DEFAULT_GUI_FONT); SelectObject(dc,font);
    const wchar_t* dev = selected==Device::Head?L"HEAD":selected==Device::Left?L"LEFT HAND":L"RIGHT HAND";
    wchar_t buf[2048];
    swprintf_s(buf,
      L"VR Keyboard Emulator\n\nSelected: %s\n\n"
      L"1 / F1  Head\n2 / F2  Left hand\n3 / F3  Right hand\n\n"
      L"WASD    Move horizontally\nQ / E   Down / Up\nArrows  Yaw / Pitch\nZ / X   Roll\nShift   Fast movement\nR       Reset selected device\n\n"
      L"Controller inputs (when a hand is selected):\n"
      L"Space   Trigger\nCtrl    Grip\nF       Primary (A/X)\nG       Secondary (B/Y)\nTab     Menu\nC       Stick click\nI/J/K/L Joystick\n\n"
      L"Keep this app running, then launch SteamVR.\n"
      L"Use SteamVR's VR View / game mirror to see the rendered output on your monitor.", dev);
    DrawTextW(dc, buf, -1, &r, DT_LEFT|DT_TOP|DT_NOPREFIX);
    EndPaint(hwnd,&ps);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch(msg) {
    case WM_PAINT: Paint(hwnd); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}

} // namespace

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int show) {
    mapping = OpenOrCreateMapping(true);
    if (!mapping.state) { MessageBoxW(nullptr,L"Could not create shared state.",L"VRKBD",MB_ICONERROR); return 1; }

    WNDCLASSW wc{}; wc.lpfnWndProc=WndProc; wc.hInstance=inst; wc.lpszClassName=L"VRKBDController"; wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
    RegisterClassW(&wc);
    HWND hwnd=CreateWindowExW(0,wc.lpszClassName,L"VR Keyboard Emulator Controller",WS_OVERLAPPEDWINDOW,
                              CW_USEDEFAULT,CW_USEDEFAULT,620,650,nullptr,nullptr,inst,nullptr);
    ShowWindow(hwnd,show);

    LARGE_INTEGER freq{}, prev{}, now{}; QueryPerformanceFrequency(&freq); QueryPerformanceCounter(&prev);
    MSG msg{}; bool running=true; bool prevR=false;
    while(running) {
        while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)) { if(msg.message==WM_QUIT){running=false;break;} TranslateMessage(&msg); DispatchMessageW(&msg); }
        if(!running) break;
        QueryPerformanceCounter(&now); double dt=double(now.QuadPart-prev.QuadPart)/double(freq.QuadPart); prev=now; dt=std::min(dt,0.05);

        if(Key('1')||Key(VK_F1)) selected=Device::Head;
        if(Key('2')||Key(VK_F2)) selected=Device::Left;
        if(Key('3')||Key(VK_F3)) selected=Device::Right;

        PoseState* p = selected==Device::Head ? &mapping.state->head : (selected==Device::Left ? &mapping.state->left.pose : &mapping.state->right.pose);
        Move(*p,dt);
        bool r=Key('R'); if(r&&!prevR) ResetSelected(); prevR=r;

        if(selected!=Device::Head) {
            ControllerState& c = selected==Device::Left ? mapping.state->left : mapping.state->right;
            c.trigger = Key(VK_SPACE)?1.0f:0.0f;
            c.grip = Key(VK_CONTROL)?1.0f:0.0f;
            c.buttons = (Key('F')?1u:0u) | (Key('G')?2u:0u) | (Key(VK_TAB)?4u:0u) | (Key('C')?8u:0u);
            c.joyX = (Key('L')?1.0f:0.0f) - (Key('J')?1.0f:0.0f);
            c.joyY = (Key('I')?1.0f:0.0f) - (Key('K')?1.0f:0.0f);
        }
        InterlockedIncrement(&mapping.state->sequence);
        mapping.state->controllerAlive = 1;
        InvalidateRect(hwnd,nullptr,FALSE);
        Sleep(4);
    }
    CloseMapping(mapping);
    return 0;
}
