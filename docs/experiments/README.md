# Experiments

## `crs-only.patch`

The first attempt at fixing enumeration enabled the Clock Recovery System and
trimmed HSI48 against USB SOF:

```c
RCC->APB1ENR |= RCC_APB1ENR_CRSEN;
CRS->CFGR = (47999U << CRS_CFGR_RELOAD_Pos) | ...;
CRS->CR = CRS_CR_AUTOTRIMEN | CRS_CR_CEN;
```

On the affected NanoVNA-H the core still never received SOF, `CRS->ISR` stayed
`0000`, and control transfers failed. It is kept here because it documents a
reasonable-looking dead end: if the USB clock domain itself is unusable, CRS
cannot recover it. The shipped fix clocks USB from PCLK instead.
