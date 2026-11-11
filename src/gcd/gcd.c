#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;
    else if (a % 2 == 0 && b % 2 == 0)
        return 2 * gcd_u32(a / 2, b / 2);
    else if (a % 2 == 0 && b % 2 != 0)
        return gcd_u32(a / 2, b);
    else if (a % 2 != 0 && b % 2 == 0)
        return gcd_u32(a, b / 2);
    else if (a >= b)
        return gcd_u32(a - b, b);
    else
        return gcd_u32(a, b - a);
}
