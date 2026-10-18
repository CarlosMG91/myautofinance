#include <windows.h>
#include <iostream>
#include <string>
#include <vector>
// Read-only check of exactly the resource queries used by the native installer.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 1;
  const DWORD size = GetFileVersionInfoSizeW(argv[1], nullptr);
  std::vector<BYTE> data(size);
  if (!size || !GetFileVersionInfoW(argv[1], 0, size, data.data())) return 2;
  for (const auto& field : std::vector<std::pair<std::wstring, std::wstring>>{
      {L"CompanyName", L"com.carlosmg91"}, {L"ProductName", L"Autofinance"},
      {L"InternalName", L"myautofinance"}, {L"OriginalFilename", L"myautofinance.exe"}}) {
    LPVOID value = nullptr; UINT length = 0;
    const auto query = L"\\StringFileInfo\\040904e4\\" + field.first;
    if (!VerQueryValueW(data.data(), query.c_str(), &value, &length) || !length ||
        static_cast<wchar_t*>(value)[length - 1] != L'\0' ||
        std::wstring(static_cast<wchar_t*>(value), length - 1) != field.second) {
      std::wcerr << L"Fixture resource mismatch: " << field.first << L"\n";
      return 3;
    }
  }
  std::cout << "Synthetic fixture identity resources verified\n";
  return 0;
}
