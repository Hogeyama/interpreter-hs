{
module Parser where
import Lexer
import Syntax
import Control.Exception.Base (throw, throwIO)
}

%name parseCmd
%tokentype { Token }
%monad { Either Error } { (>>=) } { return }
%error { parseError }

%token
    int    { TokenInt  $$  }
    bool   { TokenBool $$  }
    id     { TokenID   $$  }
    let    { TokenLet      }
    in     { TokenIn       }
    '+'    { TokenPlus     }
    '-'    { TokenMinus    }
    '*'    { TokenTimes    }
    '/'    { TokenDiv      }
    '='    { TokenEq       }
    '<'    { TokenLt       }
    if     { TokenIf       }
    then   { TokenThen     }
    else   { TokenElse     }
    '('    { TokenLParen   }
    ')'    { TokenRParen   }
    fun    { TokenFun      }
    '->'   { TokenArrow    }
    rec    { TokenRec      }
    ';;'   { TokenSemiSemi }
    '['    { TokenLBracket }
    ']'    { TokenRBracket }
    '::'   { TokenCons     }
    ','    { TokenComma    }
    match  { TokenMatch    }
    with   { TokenWith     }
    '|'    { TokenBar      }
    intT   { TokenIntT     }
    boolT  { TokenBoolT    }
    list   { TokenListT    }
    forall { TokenFolall   }
    ':'    { TokenColon    }
    '.'    { TokenDot      }
    '_'    { TokenWild     }
    and    { TokenAnd      }
    '#'    { TokenSharp    }

%right in
%nonassoc '>' '<'
%left '+' '-'
%left '*' '/'

%%

TopLevel :: { Command }
    : Expr ';;'        { CExp $1         }
    | Declare ';;'     { CDecl $1        }
    | '#' Var Var ';;' { CDirect $2 [$3] }

Declare :: { [Declare] }
    : let     DeclareUnit         { [Decl $2]       }
    | let     DeclareUnit Declare { (Decl $2):$3    }
    | let rec DeclareUnit         { [RecDecl $3]    }
    | let rec DeclareUnit Declare { (RecDecl $3):$4 }

DeclareUnit :: { [(Name,Expr)] }
    : Var Args0 '=' Expr                    { [($1, mkFun $2 $4)]   }
    | Var Args0 '=' Expr and DeclareUnit    { ($1, mkFun $2 $4):$6  }
    | Var ':' Type '=' Expr                 { [($1, EAnnot $5 $3)]  }
    | Var ':' Type '=' Expr and DeclareUnit { ($1, EAnnot $5 $3):$7 }

Expr :: { Expr }
    : let Var Args0 '=' Expr in Expr     { ELet $2 (mkFun $3 $5) $7    }
    | let Var ':' Type '=' Expr in Expr  { ELet $2 (EAnnot $6 $4) $8   }
    | let rec Var Args0 '=' Expr in Expr { ELetRec $3 (mkFun $4 $6) $8 }
    | if Expr then Expr else Expr        { EIf $2 $4 $6                }
    | fun Args1 '->' Expr                { mkFun $2 $4                 }
    | ArithExpr '=' ArithExpr            { EEq $1 $3                   }
    | ArithExpr '<' ArithExpr            { ELt $1 $3                   }
    | match Expr with Cases              { EMatch $2 $4                }
    | match Expr with '|' Cases          { EMatch $2 $5                }
    | ListExpr                           { $1                          }

Cases :: { [(Pattern, Expr)] }
    : Pattern '->' Expr           { [($1,$3)]  }
    | Pattern '->' Expr '|' Cases { ($1,$3):$5 }

Pattern :: { Pattern }
    : Pattern ':' '(' Type ')' { PAnnot $1 $4 }
    | ConsPattern              { $1           }

ConsPattern :: { Pattern }
    : AtomicPattern '::' ConsPattern { PCons $1 $3 }
    | AtomicPattern                  { $1          }

AtomicPattern :: { Pattern }
    : int                         { PInt $1     }
    | bool                        { PBool $1    }
    | Var                         { PVar $1     }
    | '(' Pattern ',' Pattern ')' { PPair $2 $4 }
    | '[' ']'                     { PNil        }
    | '(' Pattern ')'             { $2          }
    | '_'                         { PWild       }

ListExpr :: { Expr }
    : ArithExpr '::' ListExpr { ECons $1 $3 }
    | ArithExpr               { $1          }

ArithExpr :: { Expr }
    : ArithExpr '+' ArithExpr { EAdd $1 $3 }
    | ArithExpr '-' ArithExpr { ESub $1 $3 }
    | FactorExpr              { $1         }

FactorExpr :: { Expr }
    : FactorExpr '*' FactorExpr { EMul $1 $3 }
    | FactorExpr '/' FactorExpr { EMul $1 $3 }
    | AppExpr                   { $1         }

AppExpr :: { Expr }
    : AppExpr AtomicExpr { EApp $1 $2 }
    | AtomicExpr         { $1         }

AtomicExpr :: { Expr }
    : int                   { EConstInt $1  }
    | bool                  { EConstBool $1 }
    | id                    { EVar $1       }
    | '(' Expr ')'          { $2            }
    | '[' ']'               { ENil          }
    | '(' Expr ',' Expr ')' { EPair $2 $4   }

Var :: { String }
    : id { $1 }

Args0 :: { [(Name, Maybe Type)] }
    :           { []    }
    | Args1     { $1    }

Args1 :: { [(Name, Maybe Type)] }
    : Var Args0                  { ($1,Nothing):$2  }
    | '(' Var ':' Type ')' Args0 { ($2, Just $4):$6 }

TyVar :: { TyVar }
    : id { BoundTv $1 }

TyVars :: { [TyVar] }
    : id        { [BoundTv $1]    }
    | id TyVars { BoundTv $1 : $2 }

Type :: { Type }
    : forall TyVars '.' Type { Forall $2 $4 }
    | PairType '->' Type     { Fun $1 $3    }
    | PairType               { $1           }

PairType :: { Type }
    : PairType '*' PairType { TyPair $1 $3 }
    | ListType              { $1           }

ListType :: { Type }
    : ListType list { TyList $1 }
    | AtomicType    { $1        }

AtomicType :: { Type }
    : intT         { TyInt    }
    | boolT        { TyBool   }
    | TyVar        { TyVar $1 }
    | '(' Type ')' { $2       }

{

parseError :: [Token] -> Either Error a
parseError tks = Left $ Failure $ "Parse error:\n"

mkFun :: [(Name, Maybe Type)] -> Expr -> Expr
mkFun argtys e =
    let f (arg, Nothing) e = EFun arg e
        f (arg, Just ty) e = EFunAnnot arg ty e
    in foldr f e argtys

}

