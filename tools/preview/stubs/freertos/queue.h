#pragma once
typedef void *QueueHandle_t;
QueueHandle_t xQueueCreate(int n, int size);
int xQueueSend(QueueHandle_t q, const void *item, int wait);
int xQueueReceive(QueueHandle_t q, void *item, int wait);
