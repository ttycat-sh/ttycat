#pragma once
typedef void *SemaphoreHandle_t;
#define xSemaphoreCreateMutex() ((SemaphoreHandle_t)1)
#define xSemaphoreTake(a, b) (1)
#define xSemaphoreGive(a) (1)
