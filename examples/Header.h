#ifndef Header_dot_h
#define Header_dot_h

#include "Types.h"
#include <ostream>

namespace LSE {

#pragma pack(1)
struct Header
{
    Int8  start  = 0x02;
    Int16 length = 0;
    Alpha type   = 0;

    Header() = default;

    Header(uint16_t size, uint8_t type)
      : length(size - 3)
      , type(type)
    {
    }

    [[nodiscard]] size_t size() const
    {
        return length + 3;
    }
};
#pragma pack()

inline [[cppgen::auto]] std::ostream& operator<<(std::ostream& s, const Header& o)
{
    // clang-format off
    s << "[Header]=";
    s << "Start: "  << o.start  << ' ';
    s << "Length: " << o.length << ' ';
    s << "Type: "   << o.type;
    // clang-format on
    return s;
}

inline [[cppgen::auto]] std::string to_json(const Header& o, bool verbose)
{
    return std::string()
    // clang-format off
    + "{"
    + to_json("Start")  + ':' + (isnull(o.start)  ? to_json(nullptr, verbose) : to_json(o.start , verbose)) + ','
    + to_json("Length") + ':' + (isnull(o.length) ? to_json(nullptr, verbose) : to_json(o.length, verbose)) + ','
    + to_json("Type")   + ':' + (isnull(o.type)   ? to_json(nullptr, verbose) : to_json(o.type  , verbose))
    + "}";
    // clang-format on
}

} // namespace LSE

#endif
