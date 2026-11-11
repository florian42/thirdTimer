# Third Time - Productivity Timer

A minimalist web app implementing the "Third Time" productivity method.

## The Method

-  **Work** for as long or short as you like, until you want or need to break
-  **Break** for up to one-third of the time you've just worked
-  Save unused break time for later
-  Handle interruptions and big breaks (meals)

## Features

-  Flexible work/break timing
-  Break time banking system
-  Interruption handling
-  Big break support for meals
-  Clean, distraction-free interface with flat design
-  Consistent rounded corners throughout the UI
-  Customizable break fractions (1/2, 1/3, 1/4, 1/5, 1/6)

## Usage

1. Click "Start Working" to begin a work session
2. Click "Take Break" when you want to stop working
3. The app calculates your earned break time (work time ÷ 3)
4. Take your break and click "Resume Work" when ready
5. Any unused break time is saved for later

## Project Structure

```
src/
├── backend/
│   └── index.ts                   # Static file server
├── frontend/
│   ├── components/                # Components
│   ├── favicon.http.tsx            # Favicon
│   ├── index.html                  # Main app interface
│   ├── index.tsx                   # React app entry point
│   ├── style.css                   # Styling
│   └── utils/                      # Utility functions
│       └── timer-actions.ts        # Timer actions
└── shared/
    ├── types.ts                    # Shared TypeScript types
    └── utils.tsx                   # Shared utility functions
```

## Origin

This project was originally created on [Val Town](https://www.val.town) as [`florian42/thirdTimer`](https://www.val.town/x/florian42/thirdTimer), where it was created on 2025-06-10. It was imported to GitHub on 2026-11-11.
