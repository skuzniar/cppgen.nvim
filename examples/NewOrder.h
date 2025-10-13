#ifndef NewOrder_dot_h
#define NewOrder_dot_h

#include "Header.h"
#include "Types.h"
#include <cstdint>
#include <ostream>

namespace LSE {

#pragma pack(1)
struct NewOrder
{
    enum : std::uint8_t
    {
        type = 'D'
    };

    Header         header = { static_cast<uint16_t>(NewOrder::size()), type };
    String<20>     clientOrderId;
    String<11>     traderId;
    String<10>     account;
    AccountType    clearingAccount;
    Int32          instrumentId;
    Bitfield       mifidFlags;
    Bitfield       partyRoleQualifiers;
    OrderType      orderType;
    TIF            timeInForce;
    ExpirationTime expireDateTime;
    Side           side;
    Int32          orderQty;
    Int32          displayQty;
    Price          price;
    Capacity       capacity;
    UInt8          autoCancel;
    OrderSubType   orderSubType;
    Anonymity      anonymity;
    Price          stopPrice;
    Passivity      passiveOnlyOrder;
    Int32          clientId;
    Int32          investmentDecisionMaker;
    UInt8          groupId;
    Int32          minimumQuantity;
    Int32          executingTrader;
    Int32          offset;
    String<16>     reserved;

    NewOrder() = default;

    static constexpr size_t size()
    {
        return sizeof(NewOrder);
    }
};
#pragma pack()

inline [[cppgen::auto]] std::ostream& operator<<(std::ostream& s, const NewOrder& o)
{
    // clang-format off
    s << "[NewOrder]=";
    s << "Header: "                  << o.header                  << ' ';
    s << "ClientOrderId: "           << o.clientOrderId           << ' ';
    s << "TraderId: "                << o.traderId                << ' ';
    s << "Account: "                 << o.account                 << ' ';
    s << "ClearingAccount: "         << o.clearingAccount         << ' ';
    s << "InstrumentId: "            << o.instrumentId            << ' ';
    s << "MifidFlags: "              << o.mifidFlags              << ' ';
    s << "PartyRoleQualifiers: "     << o.partyRoleQualifiers     << ' ';
    s << "OrderType: "               << o.orderType               << ' ';
    s << "TimeInForce: "             << o.timeInForce             << ' ';
    s << "ExpireDateTime: "          << o.expireDateTime          << ' ';
    s << "Side: "                    << o.side                    << ' ';
    s << "OrderQty: "                << o.orderQty                << ' ';
    s << "DisplayQty: "              << o.displayQty              << ' ';
    s << "Price: "                   << o.price                   << ' ';
    s << "Capacity: "                << o.capacity                << ' ';
    s << "AutoCancel: "              << o.autoCancel              << ' ';
    s << "OrderSubType: "            << o.orderSubType            << ' ';
    s << "Anonymity: "               << o.anonymity               << ' ';
    s << "StopPrice: "               << o.stopPrice               << ' ';
    s << "PassiveOnlyOrder: "        << o.passiveOnlyOrder        << ' ';
    s << "ClientId: "                << o.clientId                << ' ';
    s << "InvestmentDecisionMaker: " << o.investmentDecisionMaker << ' ';
    s << "GroupId: "                 << o.groupId                 << ' ';
    s << "MinimumQuantity: "         << o.minimumQuantity         << ' ';
    s << "ExecutingTrader: "         << o.executingTrader         << ' ';
    s << "Offset: "                  << o.offset                  << ' ';
    s << "Reserved: "                << o.reserved;
    // clang-format on
    return s;
}

inline [[cppgen::auto]] std::string to_json(const NewOrder& o, bool verbose)
{
    return std::string()
    // clang-format off
    + "{"
    + to_json("Header")                  + ':' + (isnull(o.header)                  ? to_json(nullptr, verbose) : to_json(o.header                 , verbose)) + ','
    + to_json("ClientOrderId")           + ':' + (isnull(o.clientOrderId)           ? to_json(nullptr, verbose) : to_json(o.clientOrderId          , verbose)) + ','
    + to_json("TraderId")                + ':' + (isnull(o.traderId)                ? to_json(nullptr, verbose) : to_json(o.traderId               , verbose)) + ','
    + to_json("Account")                 + ':' + (isnull(o.account)                 ? to_json(nullptr, verbose) : to_json(o.account                , verbose)) + ','
    + to_json("ClearingAccount")         + ':' + (isnull(o.clearingAccount)         ? to_json(nullptr, verbose) : to_json(o.clearingAccount        , verbose)) + ','
    + to_json("InstrumentId")            + ':' + (isnull(o.instrumentId)            ? to_json(nullptr, verbose) : to_json(o.instrumentId           , verbose)) + ','
    + to_json("MifidFlags")              + ':' + (isnull(o.mifidFlags)              ? to_json(nullptr, verbose) : to_json(o.mifidFlags             , verbose)) + ','
    + to_json("PartyRoleQualifiers")     + ':' + (isnull(o.partyRoleQualifiers)     ? to_json(nullptr, verbose) : to_json(o.partyRoleQualifiers    , verbose)) + ','
    + to_json("OrderType")               + ':' + (isnull(o.orderType)               ? to_json(nullptr, verbose) : to_json(o.orderType              , verbose)) + ','
    + to_json("TimeInForce")             + ':' + (isnull(o.timeInForce)             ? to_json(nullptr, verbose) : to_json(o.timeInForce            , verbose)) + ','
    + to_json("ExpireDateTime")          + ':' + (isnull(o.expireDateTime)          ? to_json(nullptr, verbose) : to_json(o.expireDateTime         , verbose)) + ','
    + to_json("Side")                    + ':' + (isnull(o.side)                    ? to_json(nullptr, verbose) : to_json(o.side                   , verbose)) + ','
    + to_json("OrderQty")                + ':' + (isnull(o.orderQty)                ? to_json(nullptr, verbose) : to_json(o.orderQty               , verbose)) + ','
    + to_json("DisplayQty")              + ':' + (isnull(o.displayQty)              ? to_json(nullptr, verbose) : to_json(o.displayQty             , verbose)) + ','
    + to_json("Price")                   + ':' + (isnull(o.price)                   ? to_json(nullptr, verbose) : to_json(o.price                  , verbose)) + ','
    + to_json("Capacity")                + ':' + (isnull(o.capacity)                ? to_json(nullptr, verbose) : to_json(o.capacity               , verbose)) + ','
    + to_json("AutoCancel")              + ':' + (isnull(o.autoCancel)              ? to_json(nullptr, verbose) : to_json(o.autoCancel             , verbose)) + ','
    + to_json("OrderSubType")            + ':' + (isnull(o.orderSubType)            ? to_json(nullptr, verbose) : to_json(o.orderSubType           , verbose)) + ','
    + to_json("Anonymity")               + ':' + (isnull(o.anonymity)               ? to_json(nullptr, verbose) : to_json(o.anonymity              , verbose)) + ','
    + to_json("StopPrice")               + ':' + (isnull(o.stopPrice)               ? to_json(nullptr, verbose) : to_json(o.stopPrice              , verbose)) + ','
    + to_json("PassiveOnlyOrder")        + ':' + (isnull(o.passiveOnlyOrder)        ? to_json(nullptr, verbose) : to_json(o.passiveOnlyOrder       , verbose)) + ','
    + to_json("ClientId")                + ':' + (isnull(o.clientId)                ? to_json(nullptr, verbose) : to_json(o.clientId               , verbose)) + ','
    + to_json("InvestmentDecisionMaker") + ':' + (isnull(o.investmentDecisionMaker) ? to_json(nullptr, verbose) : to_json(o.investmentDecisionMaker, verbose)) + ','
    + to_json("GroupId")                 + ':' + (isnull(o.groupId)                 ? to_json(nullptr, verbose) : to_json(o.groupId                , verbose)) + ','
    + to_json("MinimumQuantity")         + ':' + (isnull(o.minimumQuantity)         ? to_json(nullptr, verbose) : to_json(o.minimumQuantity        , verbose)) + ','
    + to_json("ExecutingTrader")         + ':' + (isnull(o.executingTrader)         ? to_json(nullptr, verbose) : to_json(o.executingTrader        , verbose)) + ','
    + to_json("Offset")                  + ':' + (isnull(o.offset)                  ? to_json(nullptr, verbose) : to_json(o.offset                 , verbose)) + ','
    + to_json("Reserved")                + ':' + (isnull(o.reserved)                ? to_json(nullptr, verbose) : to_json(o.reserved               , verbose))
    + "}";
    // clang-format on
}

} // namespace LSE

#endif
