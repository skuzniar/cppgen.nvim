#ifndef to_json_dot_h
#define to_json_dot_h

#include <sstream>
#include <iomanip>
#include <string>
#include <array>
#include <numeric>
#include <cstddef>

namespace detail {

inline std::string
escape(const std::string& s)
{
    std::ostringstream o;
    // clang-format off
    for (char c : s) {
        switch (c) {
        case '"': o << "\\\""; break;
        case '\\': o << "\\\\"; break;
        case '\b': o << "\\b"; break;
        case '\f': o << "\\f"; break;
        case '\n': o << "\\n"; break;
        case '\r': o << "\\r"; break;
        case '\t': o << "\\t"; break;
        default:
            if ('\x00' <= c && c <= '\x1f') {
                o << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(c);
            } else {
                o << c;
            }
        }
    }
    // clang-format on
    return o.str();
}

inline std::string
to_json(std::nullptr_t, bool)
{
    return "null";
}
inline std::string
to_json(bool value, bool)
{
    return '"' + (value ? std::string("true") : std::string("false")) + '"';
}
inline std::string
to_json(int value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(long value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(long long value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(unsigned value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(unsigned long value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(unsigned long long value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(float value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(double value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(long double value, bool)
{
    return std::to_string(value);
}
inline std::string
to_json(const std::string& value, bool)
{
    return '"' + escape(value) + '"';
}
inline std::string
to_json(const std::string_view& value, bool)
{
    return '"' + escape(std::string(value)) + '"';
}
inline std::string
to_json(const char* value, bool)
{
    return '"' + escape(std::string(value)) + '"';
}

inline std::string
to_json(const char value, bool)
{
    return '"' + escape(std::string(&value, 1)) + '"';
}

template<typename T, std::size_t N>
inline std::string
to_json(const std::array<T, N>& value, bool verbose)
{
    return std::string() + "[" +
           std::accumulate(value.begin(),
                           value.end(),
                           std::string(),
                           [=](auto a, auto v) {
                               return a.empty() ? to_json(v, verbose) : std::move(a) + ',' + to_json(v, verbose);
                           }) +
           "]";
}

template<typename T>
inline std::string
to_json(const T* data, std::size_t size, bool verbose)
{
    return std::string() + "[" +
           std::accumulate(data,
                           data + size,
                           std::string(),
                           [=](auto a, auto v) {
                               return a.empty() ? to_json(v, verbose) : std::move(a) + ',' + to_json(v, verbose);
                           }) +
           "]";
}

template<std::size_t N>
inline std::string
to_json(const char (&literal)[N])
{
    return '"' + std::string(literal) + '"';
}

} // namespace detail

#endif
