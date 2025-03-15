/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * INNOVERTON.COM
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "peripheral_lite_server.h"
#include "peripheral_lite_server_app.h"
#include <stdbool.h>
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
//Firmware Version
const uint8_t majorVer = 1;
const uint8_t minorVer = 2;
const uint8_t patchVer = 0;
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define EEPROM_I2C_ADDRESS 0x50 // Base I2C address for AT24C01D
#define EEPROM_PAGE_SIZE 8 // Maximum bytes that can be written in one cycle
#define EEPROM_ADDRESS_SERIAL_NUM 0x00 // Page 1, Serial number is uint64_6
#define EEPROM_ADDRESS_RELAY_STAT 0x08 // Page 2, Data is uint8_t
#define LONG_PRESS_THRESHOLD 40
#define RESET_PRESS_THRESHOLD 400
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
volatile bool relay_status = false;
volatile uint64_t serial_num = 0;
uint64_t old_serial_Num = 0;
uint8_t initial_blink =0;
volatile uint16_t battery_percent=0;
#include "device_credentials.h"
uint8_t expected_password[PASSWORD_SIZE] = NULTRA_COMMAND_PASSWORD;
typedef char NultraHistoricalPasswordSize[(sizeof(NULTRA_COMMAND_PASSWORD) == PASSWORD_SIZE + 1) ? 1 : -1];
// Variable to hold the last password received from the client.
uint8_t user_password_received[PASSWORD_SIZE] = {0};

// Flag to indicate whether the password was verified.
bool password_verified = false;
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc1;

I2C_HandleTypeDef hi2c1;

IWDG_HandleTypeDef hiwdg;

PKA_HandleTypeDef hpka;

TIM_HandleTypeDef htim16;

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
void PeriphCommonClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_RADIO_Init(void);
static void MX_RADIO_TIMER_Init(void);
static void MX_PKA_Init(void);
static void MX_ADC1_Init(void);
static void MX_I2C1_Init(void);
static void MX_TIM16_Init(void);
static void MX_IWDG_Init(void);
static void MX_NVIC_Init(void);
/* USER CODE BEGIN PFP */
void Set_LED(const char *color);
void UpdateBatteryStatus(void);
HAL_StatusTypeDef EEPROM_Write(uint16_t mem_address, uint8_t *data,uint16_t length);
HAL_StatusTypeDef EEPROM_Read(uint16_t mem_address, uint8_t *data, uint16_t length);
HAL_StatusTypeDef EEPROM_WriteSerialNumber(uint64_t serial_num);
HAL_StatusTypeDef EEPROM_ReadSerialNumber(uint64_t *serial_num);
HAL_StatusTypeDef store_relay_status(bool status);
bool read_relay_status(void);
void Control_Relay(bool state);
void Timer16_Callback(void);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

	  bool relay_status_old = false;

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* Configure the peripherals common clocks */
  PeriphCommonClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_RADIO_Init();
  MX_RADIO_TIMER_Init();
  MX_PKA_Init();
  MX_ADC1_Init();
  MX_I2C1_Init();
  MX_TIM16_Init();
  MX_IWDG_Init();

  /* Initialize interrupts */
  MX_NVIC_Init();
  /* USER CODE BEGIN 2 */
  EEPROM_ReadSerialNumber(&serial_num);
  relay_status = read_relay_status();
  relay_status_old = relay_status;
  PERIPHERAL_LITE_SERVER_Data_t relay_statusData;
  relay_statusData.p_Payload = (uint64_t *)&relay_status;
  relay_statusData.Length = sizeof(relay_status);

  PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SWITCH, &relay_statusData);

  /* USER CODE END 2 */

  /* Init code for STM32_BLE */
  MX_APPE_Init(NULL);

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  // Prepare the data structure to update the VBATT characteristic.
  uint8_t serialNumAndVersion[11];
  for (int i = 0; i < 8; i++) {
      serialNumAndVersion[i] = (uint8_t)(serial_num >> (i * 8));
  }

  // Append the version bytes
  serialNumAndVersion[8]  = majorVer;
  serialNumAndVersion[9]  = minorVer;
  serialNumAndVersion[10] = patchVer;

  PERIPHERAL_LITE_SERVER_Data_t serial_numData;
  serial_numData.p_Payload = (uint64_t *)&serialNumAndVersion;
  serial_numData.Length = sizeof(serialNumAndVersion);

  PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SERIAL_NUM, &serial_numData);
  UpdateBatteryStatus();
  initial_blink = (battery_percent/25)+1;
  HAL_TIM_Base_Start_IT(&htim16);
  while (1)
  {
    /* USER CODE END WHILE */
    MX_APPE_Process();

    /* USER CODE BEGIN 3 */
    HAL_IWDG_Refresh(&hiwdg);


    // Use static variables to retain state across loop iterations.
    static uint32_t button_press_counter = 0;
    static GPIO_PinState last_button_state = GPIO_PIN_SET; // Assume button starts released.

    GPIO_PinState current_button_state = HAL_GPIO_ReadPin(button_GPIO_Port, button_Pin);

    // When the button is pressed, increment the counter on each iteration.
    if (current_button_state == GPIO_PIN_RESET) {
        button_press_counter++;
    }

    // Detect the transition from pressed to released.
    if (current_button_state == GPIO_PIN_SET && last_button_state == GPIO_PIN_RESET) {
        // The button was released. Check the counter.
    	if (button_press_counter >= RESET_PRESS_THRESHOLD){
//    		HAL_GPIO_WritePin(GPIOA, GO_DFU_Pin, GPIO_PIN_SET);
//    		GPIO_InitTypeDef GPIO_InitStruct = {0};
//    		  GPIO_InitStruct.Pin = GO_DFU_Pin;
//    		  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
//    		  GPIO_InitStruct.Pull = GPIO_PULLUP;
//    		  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
//    		  HAL_GPIO_Init(GO_DFU_GPIO_Port, &GPIO_InitStruct);
    		HAL_Delay (10000);  //Go to reset
    	} else if (button_press_counter >= LONG_PRESS_THRESHOLD) {
            // Long press detected: enable Timer16 to display battery level.
            initial_blink = (battery_percent / 25) + 1;
            HAL_TIM_Base_Start_IT(&htim16);
        } else {
            // Short press: toggle the relay state.
            relay_status = !relay_status;
        }
        // Reset the counter once the button is released.
        button_press_counter = 0;
    }

    // Save the current state for the next iteration.
    last_button_state = current_button_state;


    if (relay_status != relay_status_old) {
      Control_Relay(relay_status);
      relay_status_old = relay_status;
      relay_statusData.p_Payload = (uint64_t *)&relay_status;
      relay_statusData.Length = sizeof(relay_status);

      PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SWITCH, &relay_statusData);
    }
    UpdateBatteryStatus();

  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE|RCC_OSCILLATORTYPE_LSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_ON;
  RCC_OscInitStruct.LSEState = RCC_LSE_ON;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure the SYSCLKSource and SYSCLKDivider
  */
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_RC64MPLL;
  RCC_ClkInitStruct.SYSCLKDivider = RCC_RC64MPLL_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_WAIT_STATES_0) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief Peripherals Common Clock Configuration
  * @retval None
  */
void PeriphCommonClock_Config(void)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInitStruct = {0};

  /** Initializes the peripherals clock
  */
  PeriphClkInitStruct.PeriphClockSelection = RCC_PERIPHCLK_SMPS;
  PeriphClkInitStruct.SmpsDivSelection = RCC_SMPSCLK_DIV4;

  if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInitStruct) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief NVIC Configuration.
  * @retval None
  */
static void MX_NVIC_Init(void)
{
  /* RADIO_TIMER_CPU_WKUP_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(RADIO_TIMER_CPU_WKUP_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(RADIO_TIMER_CPU_WKUP_IRQn);
  /* RADIO_TIMER_ERROR_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(RADIO_TIMER_ERROR_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(RADIO_TIMER_ERROR_IRQn);
  /* RADIO_TXRX_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(RADIO_TXRX_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(RADIO_TXRX_IRQn);
  /* RADIO_TXRX_SEQ_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(RADIO_TXRX_SEQ_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(RADIO_TXRX_SEQ_IRQn);
  /* PKA_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(PKA_IRQn, 1, 0);
  HAL_NVIC_EnableIRQ(PKA_IRQn);
  /* USART1_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(USART1_IRQn, 1, 0);
  HAL_NVIC_EnableIRQ(USART1_IRQn);
}

/**
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_ChannelConfTypeDef ConfigChannel = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */

  /** Common config
  */
  hadc1.Instance = ADC1;
  hadc1.Init.ConversionType = ADC_CONVERSION_WITH_DS;
  hadc1.Init.SequenceLength = 1;
  hadc1.Init.SamplingMode = ADC_SAMPLING_AT_START;
  hadc1.Init.SampleRate = ADC_SAMPLE_RATE_16;
  hadc1.Init.InvertOutputMode = ADC_DATA_INVERT_NONE;
  hadc1.Init.Overrun = ADC_NEW_DATA_IS_LOST;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.DownSamplerConfig.DataWidth = ADC_DS_DATA_WIDTH_12_BIT;
  hadc1.Init.DownSamplerConfig.DataRatio = ADC_DS_RATIO_1;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Regular Channel
  */
  ConfigChannel.Channel = ADC_CHANNEL_VINM3;
  ConfigChannel.Rank = ADC_RANK_1;
  ConfigChannel.VoltRange = ADC_VIN_RANGE_1V2;
  ConfigChannel.CalibrationPoint.Number = ADC_CALIB_NONE;
  ConfigChannel.CalibrationPoint.Gain = 0x00;
  ConfigChannel.CalibrationPoint.Offset = 0x00;
  if (HAL_ADC_ConfigChannel(&hadc1, &ConfigChannel) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC1_Init 2 */
  ConfigChannel.VoltRange = LL_ADC_VIN_RANGE_2V4;
  /* USER CODE END ADC1_Init 2 */

}

/**
  * @brief I2C1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C1_Init(void)
{

  /* USER CODE BEGIN I2C1_Init 0 */

  /* USER CODE END I2C1_Init 0 */

  /* USER CODE BEGIN I2C1_Init 1 */

  /* USER CODE END I2C1_Init 1 */
  hi2c1.Instance = I2C1;
  hi2c1.Init.Timing = 0x00303D5B;
  hi2c1.Init.OwnAddress1 = 0;
  hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2 = 0;
  hi2c1.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c1, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Digital filter
  */
  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c1, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C1_Init 2 */

  /* USER CODE END I2C1_Init 2 */

}

/**
  * @brief IWDG Initialization Function
  * @param None
  * @retval None
  */
static void MX_IWDG_Init(void)
{

  /* USER CODE BEGIN IWDG_Init 0 */

  /* USER CODE END IWDG_Init 0 */

  /* USER CODE BEGIN IWDG_Init 1 */

  /* USER CODE END IWDG_Init 1 */
  hiwdg.Instance = IWDG;
  hiwdg.Init.Prescaler = IWDG_PRESCALER_32;
  hiwdg.Init.Window = 1250;
  hiwdg.Init.Reload = 1250;
  if (HAL_IWDG_Init(&hiwdg) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN IWDG_Init 2 */

  /* USER CODE END IWDG_Init 2 */

}

/**
  * @brief PKA Initialization Function
  * @param None
  * @retval None
  */
static void MX_PKA_Init(void)
{

  /* USER CODE BEGIN PKA_Init 0 */
  
  /* USER CODE END PKA_Init 0 */

  /* USER CODE BEGIN PKA_Init 1 */
  
  /* USER CODE END PKA_Init 1 */
  hpka.Instance = PKA;
  if (HAL_PKA_Init(&hpka) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN PKA_Init 2 */
  
  /* USER CODE END PKA_Init 2 */

}

/**
  * @brief RADIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_RADIO_Init(void)
{

  /* USER CODE BEGIN RADIO_Init 0 */

  /* USER CODE END RADIO_Init 0 */

  RADIO_HandleTypeDef hradio = {0};

  /* USER CODE BEGIN RADIO_Init 1 */

  /* USER CODE END RADIO_Init 1 */

  if (__HAL_RCC_RADIO_IS_CLK_DISABLED())
  {
    /* Radio Peripheral reset */
    __HAL_RCC_RADIO_FORCE_RESET();
    __HAL_RCC_RADIO_RELEASE_RESET();

    /* Enable Radio peripheral clock */
    __HAL_RCC_RADIO_CLK_ENABLE();
  }
  hradio.Instance = RADIO;
  HAL_RADIO_Init(&hradio);
  /* USER CODE BEGIN RADIO_Init 2 */

  /* USER CODE END RADIO_Init 2 */

}

/**
  * @brief RADIO_TIMER Initialization Function
  * @param None
  * @retval None
  */
static void MX_RADIO_TIMER_Init(void)
{

  /* USER CODE BEGIN RADIO_TIMER_Init 0 */
  
  /* USER CODE END RADIO_TIMER_Init 0 */

  RADIO_TIMER_InitTypeDef RADIO_TIMER_InitStruct = {0};

  /* USER CODE BEGIN RADIO_TIMER_Init 1 */
  
  /* USER CODE END RADIO_TIMER_Init 1 */

  if (__HAL_RCC_RADIO_IS_CLK_DISABLED())
  {
    /* Radio Peripheral reset */
    __HAL_RCC_RADIO_FORCE_RESET();
    __HAL_RCC_RADIO_RELEASE_RESET();

    /* Enable Radio peripheral clock */
    __HAL_RCC_RADIO_CLK_ENABLE();
  }
  /* Wait to be sure that the Radio Timer is active */
  while(LL_RADIO_TIMER_GetAbsoluteTime(WAKEUP) < 0x10);
  RADIO_TIMER_InitStruct.XTAL_StartupTime = 320;
  RADIO_TIMER_InitStruct.enableInitialCalibration = FALSE;
  RADIO_TIMER_InitStruct.periodicCalibrationInterval = 0;
  HAL_RADIO_TIMER_Init(&RADIO_TIMER_InitStruct);
  /* USER CODE BEGIN RADIO_TIMER_Init 2 */

  /* USER CODE END RADIO_TIMER_Init 2 */

}

/**
  * @brief TIM16 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM16_Init(void)
{

  /* USER CODE BEGIN TIM16_Init 0 */

  /* USER CODE END TIM16_Init 0 */

  /* USER CODE BEGIN TIM16_Init 1 */

  /* USER CODE END TIM16_Init 1 */
  htim16.Instance = TIM16;
  htim16.Init.Prescaler = 32000-1;
  htim16.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim16.Init.Period = 5999;
  htim16.Init.ClockDivision = TIM_CLOCKDIVISION_DIV4;
  htim16.Init.RepetitionCounter = 0;
  htim16.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim16) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM16_Init 2 */

  /* USER CODE END TIM16_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  /* USER CODE BEGIN MX_GPIO_Init_1 */
  /* USER CODE END MX_GPIO_Init_1 */

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOB, relay_en_Pin|relay_set_Pin|relay_reset_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOA, led_r_Pin|led_g_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(ee_en_GPIO_Port, ee_en_Pin, GPIO_PIN_SET);

  /*Configure GPIO pins : relay_en_Pin relay_reset_Pin */
  GPIO_InitStruct.Pin = relay_en_Pin|relay_reset_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /*Configure GPIO pin : relay_set_Pin */
  GPIO_InitStruct.Pin = relay_set_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_PULLDOWN;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(relay_set_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pin : PA2 */
  GPIO_InitStruct.Pin = GPIO_PIN_2;
  GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  GPIO_InitStruct.Alternate = GPIO_AF7_SWDIO;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pins : led_r_Pin led_g_Pin */
  GPIO_InitStruct.Pin = led_r_Pin|led_g_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : button_Pin */
  GPIO_InitStruct.Pin = button_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(button_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : PA10 PA11 */
  GPIO_InitStruct.Pin = GPIO_PIN_10|GPIO_PIN_11;
  GPIO_InitStruct.Mode = GPIO_MODE_ANALOG;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : ee_en_Pin */
  GPIO_InitStruct.Pin = ee_en_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ee_en_GPIO_Port, &GPIO_InitStruct);

  /**/
  HAL_PWREx_DisableGPIOPullUp(PWR_GPIO_B, PWR_GPIO_BIT_3|PWR_GPIO_BIT_1);

  /**/
  HAL_PWREx_DisableGPIOPullUp(PWR_GPIO_A, PWR_GPIO_BIT_0|PWR_GPIO_BIT_8|PWR_GPIO_BIT_10|PWR_GPIO_BIT_11);

  /**/
  HAL_PWREx_DisableGPIOPullDown(PWR_GPIO_B, PWR_GPIO_BIT_3|PWR_GPIO_BIT_1);

  /**/
  HAL_PWREx_DisableGPIOPullDown(PWR_GPIO_A, PWR_GPIO_BIT_0|PWR_GPIO_BIT_8|PWR_GPIO_BIT_10|PWR_GPIO_BIT_11);

  /**/
  HAL_PWREx_EnableGPIOPullDown(PWR_GPIO_B, PWR_GPIO_BIT_2);

  /**/
  HAL_PWREx_EnableGPIOPullUp(PWR_GPIO_A, PWR_GPIO_BIT_2|PWR_GPIO_BIT_9);

  /**/
  HAL_PWREx_EnableGPIOPullUp(PWR_GPIO_B, PWR_GPIO_BIT_5);

  /*RT DEBUG GPIO_Init */
  RT_DEBUG_GPIO_Init();

  /* USER CODE BEGIN MX_GPIO_Init_2 */
  /* USER CODE END MX_GPIO_Init_2 */
}

/* USER CODE BEGIN 4 */
void Set_LED(const char *color) {
  HAL_GPIO_WritePin(GPIOA, led_r_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOA, led_g_Pin, GPIO_PIN_RESET);
  if (strcmp(color, "red") == 0) {
    HAL_GPIO_WritePin(GPIOA, led_r_Pin, GPIO_PIN_SET);
  } else if (strcmp(color, "green") == 0) {
    HAL_GPIO_WritePin(GPIOA, led_g_Pin, GPIO_PIN_SET);
  } else if (strcmp(color, "orange") == 0) {
	HAL_GPIO_WritePin(GPIOA, led_g_Pin, GPIO_PIN_SET);
	HAL_GPIO_WritePin(GPIOA, led_r_Pin, GPIO_PIN_SET);
  }
}

void UpdateBatteryStatus(void)
{
    uint32_t adc_value = 0;
    float vBatt = 0.0f;

    // Start ADC conversion
    HAL_ADC_Start(&hadc1);

    // Wait for conversion to complete
    if (HAL_ADC_PollForConversion(&hadc1, HAL_MAX_DELAY) == HAL_OK)
    {
        // Get the ADC value (assuming 12-bit ADC: max value 4095)
        adc_value = HAL_ADC_GetValue(&hadc1);
        adc_value = 4096 - adc_value;
        // Convert ADC value to voltage.
        // For a 12-bit ADC with a 1.6V reference:
        vBatt = ((float)adc_value / 4096.0f) * 3.6f;
    }

    // Stop ADC conversion
    HAL_ADC_Stop(&hadc1);

    // Map the battery voltage (vBatt in Volts) to a percentage.
    // 0.5 V  ->  0%
    // 1.5 V  ->  100%
    float batteryPercentage = 0;

    // Use a piecewise linear approximation based on typical AA battery discharge characteristics
    if (vBatt >= 1.60f)
    {
        batteryPercentage = 100.0f;
    }
    else if (vBatt >= 1.45f)
    {
        // Map 1.45V -> 60% to 1.60V -> 100%
        batteryPercentage = ((vBatt - 1.45f) / (1.60f - 1.45f)) * 40.0f + 60.0f;
    }
    else if (vBatt >= 1.10f)
    {
        // Map 1.10V -> 0% to 1.45V -> 60%
        batteryPercentage = ((vBatt - 1.10f) / (1.45f - 1.10f)) * 60.0f;
    }
    else
    {
        batteryPercentage = 0.0f;
    }


    // Convert to an unsigned 16-bit integer
    battery_percent = (uint16_t)batteryPercentage;

    // Debug print (optional)
    APP_DBG_MSG("Battery Voltage: %.2f V, Percentage: %d%%\n", vBatt, battery_percent);

    // Prepare the data structure to update the VBATT characteristic.
    PERIPHERAL_LITE_SERVER_Data_t vbattData;
    vbattData.p_Payload = (uint8_t *)&battery_percent;
    vbattData.Length = sizeof(battery_percent);

    // Update the VBATT characteristic in the GATT database.
    PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_VBATT, &vbattData);
}

HAL_StatusTypeDef EEPROM_Write(uint16_t mem_address, uint8_t *data,
                               uint16_t length) {
  uint8_t buffer[EEPROM_PAGE_SIZE + 1];

  // Limit write size to EEPROM page size
  if (length > EEPROM_PAGE_SIZE) {
    return HAL_ERROR;
  }

  // Set memory address
  buffer[0] = (uint8_t)(mem_address & 0xFF); // AT24C01D uses an 8-bit address

  // Copy data to buffer
  memcpy(&buffer[1], data, length);

  // Enable EEPROM (active low)
  HAL_GPIO_WritePin(GPIOB, ee_en_Pin, GPIO_PIN_RESET);
  HAL_Delay(1); // Delay to ensure EEPROM is ready
  // Transmit data over I2C
  HAL_StatusTypeDef status = HAL_I2C_Master_Transmit(
      &hi2c1, EEPROM_I2C_ADDRESS << 1, buffer, length + 1, HAL_MAX_DELAY);

  // Add delay to ensure the write cycle is complete
  HAL_Delay(5); // Adjust based on EEPROM write cycle time if needed
  // Disable EEPROM
  HAL_GPIO_WritePin(GPIOB, ee_en_Pin, GPIO_PIN_SET);

  return status;
}

HAL_StatusTypeDef EEPROM_Read(uint16_t mem_address, uint8_t *data,
                              uint16_t length) {
  uint8_t address_buffer[1];

  // Set memory address
  address_buffer[0] = (uint8_t)(mem_address & 0xFF);

  // Enable EEPROM (active low)
  HAL_GPIO_WritePin(GPIOB, ee_en_Pin, GPIO_PIN_RESET);
  HAL_Delay(1); // Delay to ensure EEPROM is ready

  // Send memory address
  HAL_StatusTypeDef status = HAL_I2C_Master_Transmit(
      &hi2c1, EEPROM_I2C_ADDRESS << 1, address_buffer, 1, HAL_MAX_DELAY);

  if (status == HAL_OK) {
    // Receive data from EEPROM
    status = HAL_I2C_Master_Receive(&hi2c1, EEPROM_I2C_ADDRESS << 1, data,
                                    length, HAL_MAX_DELAY);
  }
  //  HAL_Delay(1); // Delay to ensure EEPROM is ready
  // Disable EEPROM
  HAL_GPIO_WritePin(GPIOB, ee_en_Pin, GPIO_PIN_SET);

  return status;
}
HAL_StatusTypeDef EEPROM_WriteSerialNumber(uint64_t serial_num) {
  uint8_t data[8];

  // Convert uint64_t to byte array (Big-Endian: MSB first)
  for (int i = 0; i < 8; i++) {
    data[i] = (uint8_t)(serial_num >> ((7 - i) * 8));
  }

  // Write the 8-byte serial number to EEPROM
  return EEPROM_Write(EEPROM_ADDRESS_SERIAL_NUM, data, sizeof(data));
}
HAL_StatusTypeDef EEPROM_ReadSerialNumber(uint64_t *serial_num) {
  uint8_t data[8];
  *serial_num = 0;

  // Read the 8-byte serial number from EEPROM
  HAL_StatusTypeDef status =
      EEPROM_Read(EEPROM_ADDRESS_SERIAL_NUM, data, sizeof(data));

  if (status == HAL_OK) {
    // Convert byte array to uint64_t (Big-Endian)
    for (int i = 0; i < 8; i++) {
      *serial_num = (*serial_num << 8) | data[i];
    }
  }

  return status;
}

HAL_StatusTypeDef store_relay_status(bool status) {
  uint8_t data =
      (status) ? 0x01 : 0x00; // Map bool to 0x01 (true) or 0x00 (false)

  // Write the single byte to EEPROM using the existing write function
  return EEPROM_Write(EEPROM_ADDRESS_RELAY_STAT, &data, 1);
}

bool read_relay_status(void) {
  uint8_t data = 0;

  // Read the single byte from EEPROM using the existing read function
  if (EEPROM_Read(EEPROM_ADDRESS_RELAY_STAT, &data, 1) == HAL_OK) {
    return (data == 0x01); // Return true if 0x01, false otherwise
  }

  // In case of read failure, return false (default)
  return false;
}

/**
 * @brief  Set or reset the relay pins.
 * @param  relay_en_state: GPIO_PIN_SET or GPIO_PIN_RESET for relay enable pin
 * @param  relay_set_state: GPIO_PIN_SET or GPIO_PIN_RESET for relay set pin
 * @param  relay_reset_state: GPIO_PIN_SET or GPIO_PIN_RESET for relay reset pin
 * @retval None
 */
void Control_Relay(bool state) {
  // Enable the relay
  HAL_GPIO_WritePin(GPIOB, relay_en_Pin, GPIO_PIN_SET);

  if (state) {
    // Set relay on
    HAL_GPIO_WritePin(GPIOB, relay_set_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIOB, relay_reset_Pin, GPIO_PIN_RESET);
  } else {
    // Reset relay
    HAL_GPIO_WritePin(GPIOB, relay_set_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOB, relay_reset_Pin, GPIO_PIN_SET);
  }
  HAL_Delay(2); // Delay for 1 second
  // Disable the relay enable pin
  HAL_GPIO_WritePin(GPIOB, relay_en_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOB, relay_set_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOB, relay_reset_Pin, GPIO_PIN_RESET);
  // Store the relay status
  if (store_relay_status(state) == HAL_OK) {
    Set_LED("");
  } else {
    Set_LED("red");
  }
}

void HAL_GPIO_EXTI_Callback(GPIO_TypeDef *GPIOx, uint16_t GPIO_Pin) {
  // Check if the interrupt is triggered by the correct button pin
  if ((GPIOx == GPIOA) && (GPIO_Pin == button_Pin)) {
    relay_status = !relay_status; // Toggle the relay status
            __HAL_GPIO_EXTI_CLEAR_IT(GPIOA,button_Pin);  // Clear the EXTI
            __HAL_GPIO_EXTI_CLEAR_FLAG(GPIOA,button_Pin);
    //        pending flag
  }
}
/**
 * Timer16_Callback
 *
 * Uses a timer interrupt to blink an LED based on a battery level,
 * represented by the variable 'initial_blink' (range 1 to 5).
 *
 * If the battery level is 3 or higher, the LED blinks green;
 * if it is lower than 3, the LED blinks red.
 *
 * A full blink cycle consists of turning the LED on and then off.
 * The blink counter (initial_blink) decrements after each off state.
 * When no blinks remain, the timer interrupt is stopped.
 */
void Timer16_Callback(void)
{
    // Static flag to keep track of the LED state across interrupts.
    // 0 = LED is off, 1 = LED is on.
    static uint8_t led_on = 0;


    // If there are still blink cycles left...
    if (initial_blink > 0)
    {
        if (!led_on)
        {
            // LED is currently off, so turn it on.
            // Select color based on battery level:
            // Use green if battery level is 3 or above; otherwise, red.
            if (battery_percent >= 30)
                Set_LED("green");
            else
                Set_LED("red");

            led_on = 1;
        }
        else
        {
            // LED is currently on, so turn it off.
            Set_LED("");
            led_on = 0;
            // Complete one blink cycle.
            initial_blink--;
        }
    }
    else
    {
        // No more blinks to perform.
        HAL_TIM_Base_Stop_IT(&htim16);
        Set_LED("");
        // Optionally reset led_on if needed for future uses:
        led_on = 0;
    }
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  Error_Handler();
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
