#include "NewOrder.h"

#include <iostream>

int
main()
{
    LSE::NewOrder order;

    std::cout << to_json(order, false) << std::endl;
    std::cout << to_json(order, true) << std::endl;

    return 0;
}


