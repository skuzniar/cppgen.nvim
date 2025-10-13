#ifndef Types_dot_h
#define Types_dot_h

#include "to_json.h"

#include <array>
#include <charconv>
#include <cstdint>
#include <ctime>

namespace LSE {

using detail::to_json;

// To demonstrate null check in JSON serialization we provide this dummy function
template<typename T>
bool
isnull(const T&)
{
    return false;
}

inline std::string
to_utcstring(const struct timeval& tv, unsigned precision = 6)
{
    char buffer[64];

    if (const auto* tvp = std::gmtime(&tv.tv_sec); tvp != nullptr) {
        auto count = std::strftime(buffer, sizeof(buffer), "%Y%m%d-%T", tvp);

        precision = std::min(precision, 9U);
        if (precision > 0) {
            std::snprintf(buffer + count, sizeof(buffer) - count, ".%.06d", tv.tv_usec);
            if (precision > 6) {
                std::fill(buffer + count + 1 + 6, buffer + count + 1 + precision, '0');
            }
            buffer[count + 1 + precision] = '\0';
        }
    } else {
        buffer[0] = '\0';
    }
    return buffer;
}

//---------------------------------------------------------------------------------------------------------------------
// Message field data types
//---------------------------------------------------------------------------------------------------------------------
#pragma pack(1)
struct Price
{
    static const long multiplier = 100'000'000;

    int64_t value = 0;

    Price() = default;

    Price& operator=(double v)
    {
        value = v * multiplier;
        return *this;
    }

    Price& operator=(std::string_view v)
    {
        auto res = std::from_chars(v.begin(), v.end(), value);
        value *= multiplier;

        if (res.ptr != v.end() && *res.ptr == '.') {
            long        lv  = 0;
            const auto* beg = std::next(res.ptr);
            res             = std::from_chars(beg, v.end(), lv);
            value += (lv * multiplier) / std::pow(10, std::distance(beg, res.ptr));
        }
        return *this;
    }

    operator double() const
    {
        auto div = std::lldiv(value, multiplier);
        return div.quot + double(div.rem) / multiplier;
    }

    friend std::ostream& operator<<(std::ostream& os, const Price& p)
    {
        os << p.value;
        return os;
    }

    friend std::string to_json(const Price& o, bool verbose)
    {
        if (verbose) {
            std::stringstream os;
            os.precision(8);
            os << std::fixed << double(o);
            return '"' + os.str() + " (" + std::to_string(o.value) + ")" + '"';
        }
        return to_json(double(o), verbose);
    }
};
#pragma pack()

#pragma pack(1)
template<size_t N>
struct String
{
    std::array<char, N> value = {};

    String() = default;

    String(std::string_view v)
    {
        *this = v;
    }

    String(const std::string& v)
    {
        *this = std::string_view(v);
    }

    String& operator=(std::string_view v)
    {
        std::size_t len = std::min(value.size(), v.size());
        std::copy(v.data(), v.data() + len, value.data());
        std::fill(value.data() + len, value.end(), '\0');
        return *this;
    }

    String& operator=(const std::string& v)
    {
        *this = std::string_view(v);
        return *this;
    }

    String& operator=(const char* v)
    {
        *this = std::string_view(v);
        return *this;
    }

    template<typename I>
    String& operator=(I v)
    {
        auto res = std::to_chars(value.data(), value.data() + value.size(), v);
        std::fill(res.ptr, value.end(), '\0');
        return *this;
    }

    operator std::string_view() const
    {
        return { value.begin(),
                 static_cast<size_t>(std::distance(value.begin(), std::find(value.begin(), value.end(), 0))) };
    }

    const char* begin() const
    {
        return value.begin();
    }
    const char* end() const
    {
        return value.end();
    }

    auto size() const
    {
        return value.size();
    }

    friend std::ostream& operator<<(std::ostream& os, const String& s)
    {
        os.write(s.value.data(),
                 static_cast<size_t>(std::distance(s.value.begin(), std::find(s.value.begin(), s.value.end(), 0))));
        return os;
    }

    friend std::string to_json(const String& o, bool verbose)
    {
        return to_json(o.operator std::string_view(), verbose);
    }
};
#pragma pack()

template<size_t N>
std::string
to_string(const String<N>& s)
{
    return std::string((std::string_view)(s));
}

#pragma pack(1)
struct Alpha
{
    char value = 0;

    Alpha() = default;
    Alpha(char c)
      : value(c)
    {
    }

    Alpha& operator=(std::string_view v)
    {
        value = v[0];
        return *this;
    }
    operator char() const
    {
        return value;
    }
    operator std::string_view() const
    {
        return { &value, 1 };
    }

    friend std::ostream& operator<<(std::ostream& os, const Alpha& t)
    {
        if (t.value != 0) {
            os << t.value;
        }
        return os;
    }

    friend std::string to_json(const Alpha& o, bool verbose)
    {
        return to_json(o.operator std::string_view(), verbose);
    }
};
#pragma pack()

#pragma pack(1)
template<typename T>
struct Int
{
    T value{};

    Int() = default;

    Int(T v)
      : value(v)
    {
    }

    Int(std::string_view v)
    {
        std::from_chars(v.data(), v.data() + v.size(), value);
    }

    template<size_t N>
    Int(const String<N>& s)
      : Int(std::string_view(s.begin(), s.size()))
    {
    }

    Int& operator=(T v)
    {
        value = v;
        return *this;
    }

    Int& operator+=(T v)
    {
        value += v;
        return *this;
    }

    Int& operator-=(T v)
    {
        value -= v;
        return *this;
    }

    Int& operator=(std::string_view v)
    {
        std::from_chars(v.data(), v.data() + v.size(), value);
        return *this;
    }
    operator T() const
    {
        return value;
    }

    friend std::ostream& operator<<(std::ostream& os, const Int& i)
    {
        if constexpr (std::is_same_v<int8_t, decltype(i.value)>) {
            os << int(i.value);
        } else if constexpr (std::is_same_v<uint8_t, decltype(i.value)>) {
            os << unsigned(i.value);
        } else {
            os << i.value;
        }
        return os;
    }

    inline std::string to_json(const Int<T>& o, bool)
    {
        return to_string(o);
    }
};
#pragma pack()

template<typename T>
std::string
to_string(const Int<T>& o)
{
    if constexpr (std::is_same_v<int8_t, T>) {
        return std::to_string(int(o.value));
    } else if constexpr (std::is_same_v<uint8_t, T>) {
        return std::to_string(unsigned(o.value));
    } else {
        return std::to_string(o.value);
    }
}

using Bitfield = Int<uint8_t>;

using Int8   = Int<int8_t>;
using UInt8  = Int<uint8_t>;
using Int16  = Int<int16_t>;
using UInt16 = Int<uint16_t>;
using Int32  = Int<int32_t>;
using UInt32 = Int<uint32_t>;
using Int64  = Int<int64_t>;
using UInt64 = Int<uint64_t>;

struct RejectCode
{
    char type;
    int  code;

    RejectCode(char type, int code)
      : type(type)
      , code(code)
    {
    }
};

#pragma pack(1)
struct ExpirationTime
{
    uint32_t value;

    ExpirationTime() = default;

    ExpirationTime(uint32_t v)
      : value(v)
    {
    }

    ExpirationTime& operator=(uint32_t v)
    {
        value = v;
        return *this;
    }

    ExpirationTime& operator=(std::string_view v)
    {
        std::from_chars(v.data(), v.data() + v.size(), value);
        return *this;
    }
    operator int() const
    {
        return value;
    }

    operator std::string_view() const
    {
        std::time_t t = value;

        static thread_local char buffer[32];
        if (const auto* tvp = std::gmtime(&t); tvp != nullptr) {
            std::strftime(buffer, sizeof(buffer), "%Y%m%d-%T", tvp);
        } else {
            buffer[0] = '\0';
        }
        return buffer;
    }

    friend std::ostream& operator<<(std::ostream& os, const ExpirationTime& i)
    {
        os << std::string_view(i);
        return os;
    }

    friend std::string to_json(const ExpirationTime& o, bool verbose)
    {
        return to_json(o.operator std::string_view(), verbose);
    }
};
#pragma pack()

#pragma pack(1)
struct TransactionTime
{
    uint64_t value;

    TransactionTime() = default;

    TransactionTime(uint64_t v)
      : value(v)
    {
    }

    TransactionTime& operator=(uint64_t v)
    {
        value = v;
        return *this;
    }

    TransactionTime& operator=(std::string_view v)
    {
        std::from_chars(v.data(), v.data() + v.size(), value);
        return *this;
    }

    operator timeval() const
    {
        return { static_cast<time_t>(value & 0x00000000ffffffff), static_cast<suseconds_t>(value >> 32) };
    }

    friend std::ostream& operator<<(std::ostream& os, const TransactionTime& i)
    {
        return os << to_utcstring(i);
    }

    friend std::string to_json(const TransactionTime& o, bool verbose)
    {
        return to_json(to_utcstring(o), verbose);
    }
};
#pragma pack()

template<typename T>
T from_string(std::string_view);

enum class Side : uint8_t
{
    Buy  = 1,
    Sell = 2
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, Side o)
{
    switch (o) {
            // clang-format off
        case Side::Buy:  s << "1(Buy)";  break;
        case Side::Sell: s << "2(Sell)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<Side>>(o)) + "(Invalid Side)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(Side o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case Side::Buy:  return to_json("1(Buy)" , verbose); break;
            case Side::Sell: return to_json("2(Sell)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<Side>>(o)) + "(Invalid Side)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case Side::Buy:  return to_json(1, verbose); break;
            case Side::Sell: return to_json(2, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<Side>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class AccountType : uint8_t
{
    Client = 1,
    House  = 3
};

inline [[cppgen::auto]] std::string to_json(AccountType o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case AccountType::Client: return to_json("1(Client)", verbose); break;
            case AccountType::House:  return to_json("3(House)" , verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<AccountType>>(o)) + "(Invalid AccountType)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case AccountType::Client: return to_json(1, verbose); break;
            case AccountType::House:  return to_json(3, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<AccountType>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, AccountType o)
{
    switch (o) {
            // clang-format off
        case AccountType::Client: s << "1(Client)"; break;
        case AccountType::House:  s << "3(House)";  break;
        default: s << std::to_string(static_cast<std::underlying_type_t<AccountType>>(o)) + "(Invalid AccountType)"; break;
            // clang-format on
    };
    return s;
}

enum class TIF : uint8_t
{
    DAY = 0,
    IOC = 3,
    FOK = 4,
    OPG = 5,
    GTD = 6,
    GTT = 8,
    ATC = 10,
    CPX = 12,
    GFA = 50,
    GFX = 51,
    GFS = 52
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, TIF o)
{
    switch (o) {
            // clang-format off
        case TIF::DAY: s << "0(DAY)";  break;
        case TIF::IOC: s << "3(IOC)";  break;
        case TIF::FOK: s << "4(FOK)";  break;
        case TIF::OPG: s << "5(OPG)";  break;
        case TIF::GTD: s << "6(GTD)";  break;
        case TIF::GTT: s << "8(GTT)";  break;
        case TIF::ATC: s << "10(ATC)"; break;
        case TIF::CPX: s << "12(CPX)"; break;
        case TIF::GFA: s << "50(GFA)"; break;
        case TIF::GFX: s << "51(GFX)"; break;
        case TIF::GFS: s << "52(GFS)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<TIF>>(o)) + "(Invalid TIF)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(TIF o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case TIF::DAY: return to_json("0(DAY)" , verbose); break;
            case TIF::IOC: return to_json("3(IOC)" , verbose); break;
            case TIF::FOK: return to_json("4(FOK)" , verbose); break;
            case TIF::OPG: return to_json("5(OPG)" , verbose); break;
            case TIF::GTD: return to_json("6(GTD)" , verbose); break;
            case TIF::GTT: return to_json("8(GTT)" , verbose); break;
            case TIF::ATC: return to_json("10(ATC)", verbose); break;
            case TIF::CPX: return to_json("12(CPX)", verbose); break;
            case TIF::GFA: return to_json("50(GFA)", verbose); break;
            case TIF::GFX: return to_json("51(GFX)", verbose); break;
            case TIF::GFS: return to_json("52(GFS)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<TIF>>(o)) + "(Invalid TIF)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case TIF::DAY: return to_json(0 , verbose); break;
            case TIF::IOC: return to_json(3 , verbose); break;
            case TIF::FOK: return to_json(4 , verbose); break;
            case TIF::OPG: return to_json(5 , verbose); break;
            case TIF::GTD: return to_json(6 , verbose); break;
            case TIF::GTT: return to_json(8 , verbose); break;
            case TIF::ATC: return to_json(10, verbose); break;
            case TIF::CPX: return to_json(12, verbose); break;
            case TIF::GFA: return to_json(50, verbose); break;
            case TIF::GFX: return to_json(51, verbose); break;
            case TIF::GFS: return to_json(52, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<TIF>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class OrderType : uint8_t
{
    Market    = 1,
    Limit     = 2,
    Stop      = 3,
    StopLimit = 4
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, OrderType o)
{
    switch (o) {
            // clang-format off
        case OrderType::Market:    s << "1(Market)";    break;
        case OrderType::Limit:     s << "2(Limit)";     break;
        case OrderType::Stop:      s << "3(Stop)";      break;
        case OrderType::StopLimit: s << "4(StopLimit)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<OrderType>>(o)) + "(Invalid OrderType)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(OrderType o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case OrderType::Market:    return to_json("1(Market)"   , verbose); break;
            case OrderType::Limit:     return to_json("2(Limit)"    , verbose); break;
            case OrderType::Stop:      return to_json("3(Stop)"     , verbose); break;
            case OrderType::StopLimit: return to_json("4(StopLimit)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<OrderType>>(o)) + "(Invalid OrderType)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case OrderType::Market:    return to_json(1, verbose); break;
            case OrderType::Limit:     return to_json(2, verbose); break;
            case OrderType::Stop:      return to_json(3, verbose); break;
            case OrderType::StopLimit: return to_json(4, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<OrderType>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class OrderSubType : uint8_t
{
    Order      = 0,
    Quote      = 3,
    Pegged     = 5,
    RandomPeak = 51,
    Offset     = 55
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, OrderSubType o)
{
    switch (o) {
            // clang-format off
        case OrderSubType::Order:      s << "0(Order)";       break;
        case OrderSubType::Quote:      s << "3(Quote)";       break;
        case OrderSubType::Pegged:     s << "5(Pegged)";      break;
        case OrderSubType::RandomPeak: s << "51(RandomPeak)"; break;
        case OrderSubType::Offset:     s << "55(Offset)";     break;
        default: s << std::to_string(static_cast<std::underlying_type_t<OrderSubType>>(o)) + "(Invalid OrderSubType)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(OrderSubType o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case OrderSubType::Order:      return to_json("0(Order)"      , verbose); break;
            case OrderSubType::Quote:      return to_json("3(Quote)"      , verbose); break;
            case OrderSubType::Pegged:     return to_json("5(Pegged)"     , verbose); break;
            case OrderSubType::RandomPeak: return to_json("51(RandomPeak)", verbose); break;
            case OrderSubType::Offset:     return to_json("55(Offset)"    , verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<OrderSubType>>(o)) + "(Invalid OrderSubType)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case OrderSubType::Order:      return to_json(0 , verbose); break;
            case OrderSubType::Quote:      return to_json(3 , verbose); break;
            case OrderSubType::Pegged:     return to_json(5 , verbose); break;
            case OrderSubType::RandomPeak: return to_json(51, verbose); break;
            case OrderSubType::Offset:     return to_json(55, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<OrderSubType>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class Capacity : uint8_t
{
    MTCH = 1,
    DEAL = 2,
    AOTC = 3
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, Capacity o)
{
    switch (o) {
            // clang-format off
        case Capacity::MTCH: s << "1(MTCH)"; break;
        case Capacity::DEAL: s << "2(DEAL)"; break;
        case Capacity::AOTC: s << "3(AOTC)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<Capacity>>(o)) + "(Invalid Capacity)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(Capacity o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case Capacity::MTCH: return to_json("1(MTCH)", verbose); break;
            case Capacity::DEAL: return to_json("2(DEAL)", verbose); break;
            case Capacity::AOTC: return to_json("3(AOTC)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<Capacity>>(o)) + "(Invalid Capacity)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case Capacity::MTCH: return to_json(1, verbose); break;
            case Capacity::DEAL: return to_json(2, verbose); break;
            case Capacity::AOTC: return to_json(3, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<Capacity>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class Anonymity : uint8_t
{
    Anonymous = 0,
    Named     = 1
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, Anonymity o)
{
    switch (o) {
            // clang-format off
        case Anonymity::Anonymous: s << "0(Anonymous)"; break;
        case Anonymity::Named:     s << "1(Named)";     break;
        default: s << std::to_string(static_cast<std::underlying_type_t<Anonymity>>(o)) + "(Invalid Anonymity)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(Anonymity o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case Anonymity::Anonymous: return to_json("0(Anonymous)", verbose); break;
            case Anonymity::Named:     return to_json("1(Named)"    , verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<Anonymity>>(o)) + "(Invalid Anonymity)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case Anonymity::Anonymous: return to_json(0, verbose); break;
            case Anonymity::Named:     return to_json(1, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<Anonymity>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class Passivity : uint8_t
{
    NoConstraint                        = 0,
    AcceptIfNoMatch                     = 99,
    AcceptIfNewBBO                      = 100,
    AcceptIfNewOrExistingBBO            = 1,
    AcceptIfAtBBOOrWithinOnePricePoint  = 2,
    AcceptIfAtBBOOrWithinTwoPricePoints = 3
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, Passivity o)
{
    switch (o) {
            // clang-format off
        case Passivity::NoConstraint:                        s << "0(NoConstraint)";                        break;
        case Passivity::AcceptIfNoMatch:                     s << "99(AcceptIfNoMatch)";                    break;
        case Passivity::AcceptIfNewBBO:                      s << "100(AcceptIfNewBBO)";                    break;
        case Passivity::AcceptIfNewOrExistingBBO:            s << "1(AcceptIfNewOrExistingBBO)";            break;
        case Passivity::AcceptIfAtBBOOrWithinOnePricePoint:  s << "2(AcceptIfAtBBOOrWithinOnePricePoint)";  break;
        case Passivity::AcceptIfAtBBOOrWithinTwoPricePoints: s << "3(AcceptIfAtBBOOrWithinTwoPricePoints)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<Passivity>>(o)) + "(Invalid Passivity)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(Passivity o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case Passivity::NoConstraint:                        return to_json("0(NoConstraint)"                       , verbose); break;
            case Passivity::AcceptIfNoMatch:                     return to_json("99(AcceptIfNoMatch)"                   , verbose); break;
            case Passivity::AcceptIfNewBBO:                      return to_json("100(AcceptIfNewBBO)"                   , verbose); break;
            case Passivity::AcceptIfNewOrExistingBBO:            return to_json("1(AcceptIfNewOrExistingBBO)"           , verbose); break;
            case Passivity::AcceptIfAtBBOOrWithinOnePricePoint:  return to_json("2(AcceptIfAtBBOOrWithinOnePricePoint)" , verbose); break;
            case Passivity::AcceptIfAtBBOOrWithinTwoPricePoints: return to_json("3(AcceptIfAtBBOOrWithinTwoPricePoints)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<Passivity>>(o)) + "(Invalid Passivity)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case Passivity::NoConstraint:                        return to_json(0  , verbose); break;
            case Passivity::AcceptIfNoMatch:                     return to_json(99 , verbose); break;
            case Passivity::AcceptIfNewBBO:                      return to_json(100, verbose); break;
            case Passivity::AcceptIfNewOrExistingBBO:            return to_json(1  , verbose); break;
            case Passivity::AcceptIfAtBBOOrWithinOnePricePoint:  return to_json(2  , verbose); break;
            case Passivity::AcceptIfAtBBOOrWithinTwoPricePoints: return to_json(3  , verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<Passivity>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class ExecType : char
{
    New         = '0',
    Canceled    = '4',
    Replaced    = '5',
    Rejected    = '8',
    Expired     = 'C',
    Restated    = 'D',
    Trade       = 'F',
    TradeCancel = 'H',
    Suspended   = '9'
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, ExecType o)
{
    switch (o) {
            // clang-format off
        case ExecType::New:         s << "'0'(New)";         break;
        case ExecType::Canceled:    s << "'4'(Canceled)";    break;
        case ExecType::Replaced:    s << "'5'(Replaced)";    break;
        case ExecType::Rejected:    s << "'8'(Rejected)";    break;
        case ExecType::Expired:     s << "'C'(Expired)";     break;
        case ExecType::Restated:    s << "'D'(Restated)";    break;
        case ExecType::Trade:       s << "'F'(Trade)";       break;
        case ExecType::TradeCancel: s << "'H'(TradeCancel)"; break;
        case ExecType::Suspended:   s << "'9'(Suspended)";   break;
        default: s << std::to_string(static_cast<std::underlying_type_t<ExecType>>(o)) + "(Invalid ExecType)"; break;
            // clang-format on
    };
    return s;
}

enum class LastMarket : uint8_t
{
    XLON = 21,
    XLOM = 22,
    AIMX = 23
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, LastMarket o)
{
    switch (o) {
            // clang-format off
        case LastMarket::XLON: s << "21(XLON)"; break;
        case LastMarket::XLOM: s << "22(XLOM)"; break;
        case LastMarket::AIMX: s << "23(AIMX)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<LastMarket>>(o)) + "(Invalid LastMarket)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(LastMarket o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case LastMarket::XLON: return to_json("21(XLON)", verbose); break;
            case LastMarket::XLOM: return to_json("22(XLOM)", verbose); break;
            case LastMarket::AIMX: return to_json("23(AIMX)", verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<LastMarket>>(o)) + "(Invalid LastMarket)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case LastMarket::XLON: return to_json(21, verbose); break;
            case LastMarket::XLOM: return to_json(22, verbose); break;
            case LastMarket::AIMX: return to_json(23, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<LastMarket>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

enum class TradeType : uint8_t
{
    Visible      = 0,
    Hidden       = 1,
    NotSpecified = 2
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, TradeType o)
{
    switch (o) {
            // clang-format off
        case TradeType::Visible:      s << "0(Visible)";      break;
        case TradeType::Hidden:       s << "1(Hidden)";       break;
        case TradeType::NotSpecified: s << "2(NotSpecified)"; break;
        default: s << std::to_string(static_cast<std::underlying_type_t<TradeType>>(o)) + "(Invalid TradeType)"; break;
            // clang-format on
    };
    return s;
}

enum class LSEOrderStatus : uint8_t
{
    New             = 0,
    PartiallyFilled = 1,
    Filled          = 2,
    Canceled        = 4,
    Expired         = 6,
    Rejected        = 8,
    Suspended       = 9
};

inline [[cppgen::auto]] std::ostream&
operator<<(std::ostream& s, LSEOrderStatus o)
{
    switch (o) {
            // clang-format off
        case LSEOrderStatus::New:             s << "0(New)";             break;
        case LSEOrderStatus::PartiallyFilled: s << "1(PartiallyFilled)"; break;
        case LSEOrderStatus::Filled:          s << "2(Filled)";          break;
        case LSEOrderStatus::Canceled:        s << "4(Canceled)";        break;
        case LSEOrderStatus::Expired:         s << "6(Expired)";         break;
        case LSEOrderStatus::Rejected:        s << "8(Rejected)";        break;
        case LSEOrderStatus::Suspended:       s << "9(Suspended)";       break;
        default: s << std::to_string(static_cast<std::underlying_type_t<LSEOrderStatus>>(o)) + "(Invalid LSEOrderStatus)"; break;
            // clang-format on
    };
    return s;
}

inline [[cppgen::auto]] std::string to_json(LSEOrderStatus o, bool verbose)
{
    if (verbose) {
        switch(o)
        {
        // clang-format off
            case LSEOrderStatus::New:             return to_json("0(New)"            , verbose); break;
            case LSEOrderStatus::PartiallyFilled: return to_json("1(PartiallyFilled)", verbose); break;
            case LSEOrderStatus::Filled:          return to_json("2(Filled)"         , verbose); break;
            case LSEOrderStatus::Canceled:        return to_json("4(Canceled)"       , verbose); break;
            case LSEOrderStatus::Expired:         return to_json("6(Expired)"        , verbose); break;
            case LSEOrderStatus::Rejected:        return to_json("8(Rejected)"       , verbose); break;
            case LSEOrderStatus::Suspended:       return to_json("9(Suspended)"      , verbose); break;
            default: return to_json(std::to_string(static_cast<std::underlying_type_t<LSEOrderStatus>>(o)) + "(Invalid LSEOrderStatus)", verbose); break;
        // clang-format on
        };
    } else {
        switch(o)
        {
        // clang-format off
            case LSEOrderStatus::New:             return to_json(0, verbose); break;
            case LSEOrderStatus::PartiallyFilled: return to_json(1, verbose); break;
            case LSEOrderStatus::Filled:          return to_json(2, verbose); break;
            case LSEOrderStatus::Canceled:        return to_json(4, verbose); break;
            case LSEOrderStatus::Expired:         return to_json(6, verbose); break;
            case LSEOrderStatus::Rejected:        return to_json(8, verbose); break;
            case LSEOrderStatus::Suspended:       return to_json(9, verbose); break;
            default: return to_json(static_cast<std::underlying_type_t<LSEOrderStatus>>(o), verbose); break;
        // clang-format on
        };
    }
    return to_json("", verbose);
}

} // namespace LSE

#endif
