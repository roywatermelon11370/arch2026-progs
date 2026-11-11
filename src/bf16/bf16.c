#include "bf16.h"

#define BF16_SIGN_MASK 0x8000u
#define BF16_EXP_MASK 0x7F80u
#define BF16_FRAC_MASK 0x007Fu
#define BF16_EXP_BIAS 127
#define BF16_HIDDEN_BIT 0x0080u
#define BF16_INF BF16_EXP_MASK
#define BF16_NAN 0x7FC0u

uint16_t bf16_from_f32(uint32_t f32bits)
{
    /* Infinities and NaNs keep their upper bits verbatim. */
    if ((f32bits & 0x7F800000u) != 0x7F800000u)
        f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

/* Unpack a nonzero finite magnitude into an 8-bit significand and a
 * possibly nonpositive biased exponent.
 */
static uint32_t unpack_finite(uint16_t magnitude, int *exp)
{
    uint32_t significand = magnitude & BF16_FRAC_MASK;
    *exp = magnitude >> 7;
    if (*exp != 0)
        return significand | BF16_HIDDEN_BIT;

    /* Denormals use the scale of exponent field 1, with no hidden bit. */
    *exp = 1;
    while (significand < BF16_HIDDEN_BIT) {
        significand <<= 1;
        --*exp;
    }
    return significand;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (a ^ b) & BF16_SIGN_MASK;
    uint16_t mag_a = a & ~BF16_SIGN_MASK;
    uint16_t mag_b = b & ~BF16_SIGN_MASK;

    /* An infinity in a takes precedence over a NaN in b. */
    if (mag_a >= BF16_INF) {
        if (mag_a > BF16_INF)
            return a;
        return mag_b == 0 ? BF16_NAN : sign | BF16_INF;
    }
    if (mag_b >= BF16_INF) {
        if (mag_b > BF16_INF)
            return b;
        return mag_a == 0 ? BF16_NAN : sign | BF16_INF;
    }
    if (mag_a == 0 || mag_b == 0)
        return sign;

    int exp_a, exp_b;
    uint32_t sig_a = unpack_finite(mag_a, &exp_a);
    uint32_t sig_b = unpack_finite(mag_b, &exp_b);
    uint32_t product = sig_a * sig_b;
    int exp = exp_a + exp_b - BF16_EXP_BIAS;
    if (product >= (1u << 15)) {
        product >>= 1;
        ++exp;
    }

    uint32_t fraction = (product >> 7) & BF16_FRAC_MASK;
    if (exp >= 0xFF)
        return sign | BF16_INF;
    /* The contract shifts only the stored fraction on underflow. */
    if (exp <= 0)
        return exp < -6 ? sign : sign | (fraction >> (1 - exp));
    return sign | ((uint32_t) exp << 7) | fraction;
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint16_t magnitude = a & ~BF16_SIGN_MASK;
    if (magnitude > BF16_INF || a == BF16_INF)
        return a;
    if (magnitude == 0)
        return 0;
    if (a & BF16_SIGN_MASK)
        return BF16_NAN;
    if (magnitude < BF16_HIDDEN_BIT)
        return 0;

    int exp = (a >> 7) - BF16_EXP_BIAS;
    uint32_t significand = (a & BF16_FRAC_MASK) | BF16_HIDDEN_BIT;
    if (exp % 2 != 0) {
        significand <<= 1;
        --exp;
    }
    int result_exp = exp / 2 + BF16_EXP_BIAS;

    uint32_t low = 90, high = 256, result = BF16_HIDDEN_BIT;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if ((mid * mid) / BF16_HIDDEN_BIT <= significand) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* For normal inputs, result is in [128, 255] and result_exp in [64, 190].
     */
    return ((uint32_t) result_exp << 7) | (result & BF16_FRAC_MASK);
}
