node Tool {
    has name: str;
}

walker HelloTool {
    can start with Root entry {
        t = here ++> Tool(name="BudgetCalc");
        visit [-->];
    }
    can greet with Tool entry {
        print(f"Visited tool: {here.name}");
        report here.name;
    }
}

with entry {
    result = root spawn HelloTool();
    print(result.reports);
}
